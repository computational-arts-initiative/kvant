module Kvant.Tiles exposing (..)


import Array exposing (Array)
import Dict exposing (Dict)
import Set exposing (Set)


import Kvant.Plane exposing (Plane, Offset)
import Kvant.Adjacency as Adjacency exposing (Adjacency)
import Kvant.Neighbours exposing (Cardinal(..))
import Kvant.Neighbours as Neighbours
import Kvant.Direction as D exposing (Direction(..))
import Kvant.Matches as Matches exposing (Matches)
import Kvant.Rotation as Rotation exposing (Rotation(..), RotationId)
import Kvant.Symmetry as Symmetry exposing (Symmetry(..))
import List
import Dict



type alias TileKey = String


type alias Format = String


type alias TileInfo =
    { key : String
    , symmetry : Maybe Symmetry
    , weight : Maybe Float
    }


type alias TileSet = ( Format, List TileInfo )


type alias TilesPlane = Plane (TileKey, Rotation)


type alias TileAdjacency = Adjacency (TileKey, RotationId) (TileKey, Rotation)


type alias TileGrid = Array (Array (TileKey, Rotation))


type alias Rule =
    { left : ( TileKey, Rotation )
    , right : ( TileKey, Rotation )
    }



type alias TileMapping =
    ( Dict Int ( TileKey, Rotation )
    , Dict ( TileKey, RotationId ) Int -- RotationId is comparable, while Rotation is not
    )


noTile : TileKey
noTile = "none"


buildMapping : TileSet -> TileMapping
buildMapping =
    Tuple.second
        >> List.concatMap
            (\tile ->
                Rotation.uniqueFor (tile.symmetry |> Maybe.withDefault Symmetry.default)
                    |> List.map (Tuple.pair tile.key)
            )
        >> List.indexedMap
            (\index ( key, rot ) ->
                ( ( index, ( key, rot ) )
                , ( ( key, Rotation.toId rot ), index )
                )
            )
        >> (\list ->
                ( List.map Tuple.first <| list
                , List.map Tuple.second <| list
                )
           )
        >> Tuple.mapBoth Dict.fromList Dict.fromList


noMapping : TileMapping
noMapping = ( Dict.empty, Dict.empty )


toIndexInSet : TileMapping -> ( TileKey, RotationId ) -> Int
toIndexInSet ( _, toIndex ) key =
    Dict.get key toIndex |> Maybe.withDefault -1


fromIndexInSet : TileMapping -> Int -> ( TileKey, Rotation )
fromIndexInSet ( fromIndex , _ ) key =
    Dict.get key fromIndex |> Maybe.withDefault ( noTile, Original )


toIndexGrid : TileMapping -> Array (Array ( TileKey, Rotation )) -> Array (Array Int)
toIndexGrid tileMapping =
    Array.map << Array.map <| toIndexInSet tileMapping


fromIndexGrid : TileMapping -> Array (Array Int) -> Array (Array ( TileKey, Rotation ))
fromIndexGrid tileMapping =
    Array.map << Array.map <| fromIndexInSet tileMapping



keyRotFromString : String -> ( TileKey, Rotation )
keyRotFromString str =
    case String.split " " str of
        key::rotation::_ ->
            ( key, String.toInt rotation |> Maybe.withDefault 0 )
        [ key ] ->
            ( key, 0 )
        [] ->
            ( noTile, 0 )


rotateTileTo : Direction -> ( TileKey, Rotation ) -> ( TileKey, Rotation )
rotateTileTo =
    Tuple.mapSecond << Rotation.to


allowedByRule : Rule -> ( TileKey, Rotation ) -> ( TileKey, Rotation ) -> Bool
allowedByRule { left, right } ( tileAtLeft, rotationAtLeft ) ( tileAtRight, rotationAtRight )
    = case ( left, right ) of
        ( ( requiredAtLeft, requiredRotationAtLeft ), ( requiredAtRight, requiredRotationAtRight ) ) ->
            requiredAtLeft == tileAtLeft
                && requiredAtRight == tileAtRight
                && requiredRotationAtLeft == rotationAtLeft
                && requiredRotationAtRight == rotationAtRight


allowedByRules : List Rule -> Direction -> ( TileKey, Rotation ) -> ( TileKey, Rotation ) -> Bool
allowedByRules rules dir leftTile rightTile =
    (rules
        |> List.filter
            (\rule ->
                allowedByRule
                    rule
                    (rotateTileTo dir leftTile)
                    (rotateTileTo dir rightTile)
            )
        |> List.length) > 0


findMatches
    :  List TileInfo
    -> List Rule
    -> ( TileInfo, Rotation )
    -> Dict Offset (Matches (TileKey, Rotation))
findMatches tiles rules ( currentTile, currentRotation ) =
    Neighbours.cardinal
        |> List.foldl
            (\dir neighbours ->
                let
                    byRules
                        = tiles
                            |> List.foldl
                                (\otherTile neighbours_ ->
                                    List.range 0 (maxRotations - 1)
                                        |> List.foldl
                                            (\otherRotation neighbours__ ->
                                                if
                                                    allowedByRules
                                                        rules
                                                        dir
                                                        ( currentTile.key, currentRotation )
                                                        ( otherTile.key, otherRotation )
                                                    || allowedByRules
                                                        rules
                                                        (D.opposite dir)
                                                        ( otherTile.key, otherRotation )
                                                        ( currentTile.key, currentRotation )
                                                    then neighbours__
                                                        |> Neighbours.at dir
                                                            ((::) ( otherTile.key, otherRotation ))
                                                    else neighbours__
                                            )
                                            neighbours_

                                )
                                neighbours
                in byRules
            )
            (Neighbours.fill [])
        |> Neighbours.map Matches.fromList
        |> Neighbours.toDict


mergeBySymmetry
    :   { subject: ( Symmetry, ( TileKey, Rotation ) )
        , weight : Float
        , matches : Dict Offset (Matches ( TileKey, Rotation ) )
        }
    -> Adjacency
            ( TileKey, Rotation )
            ( Symmetry, ( TileKey, Rotation ) )
    -> Adjacency
            ( TileKey, Rotation )
            ( Symmetry, ( TileKey, Rotation ) )
mergeBySymmetry tile adjacencySoFar =
    let
        ( symmetry, ( key, currentRotation ) ) = tile.subject
    in
        similarRotationsBySymmetry currentRotation symmetry
            |> List.foldl
                (\anotherRotation adjacency_ ->
                    Maybe.map2
                        Adjacency.merge
                        (adjacency_
                            |> Dict.get ( key, currentRotation )
                            |> Maybe.map .matches)
                        (adjacency_
                            |> Dict.get ( key, anotherRotation )
                            |> Maybe.map .matches)
                    |> Maybe.map
                        (\mergedMatches ->
                            adjacency_ |>
                                Dict.insert
                                    ( key, currentRotation )
                                    { subject = tile.subject
                                    , weight = tile.weight
                                    , matches = mergedMatches
                                    }
                        )
                    |> Maybe.withDefault adjacency_
                )
                adjacencySoFar


buildAdjacencyRules : List TileInfo -> List Rule -> TileAdjacency
buildAdjacencyRules tiles rules =
    let
        rulesApplied =
            tiles
                |> List.concatMap
                    (\tile ->
                        List.range 0 (maxRotations - 1)
                            |> List.map (\rotation ->
                                    ( ( tile.key, rotation ), tile )
                                )
                    )
                |> Dict.fromList
                |> Dict.map
                    (\(tileKey, rotation) tile ->
                        { subject = ( tile.symmetry |> Maybe.withDefault Q, ( tileKey, rotation ) )
                        , weight = tile.weight |> Maybe.withDefault 1
                        , matches = ( tile, rotation ) |> findMatches tiles rules
                        }
                    )
    in
        rulesApplied
        |> Dict.foldl (always mergeBySymmetry) rulesApplied
        |> Dict.map
            (\_ tile ->
                { subject = Tuple.second tile.subject
                , weight = tile.weight
                , matches = tile.matches
                }
            )


{-
symmetryToIndices : Symmetry -> Cardinal Int
symmetryToIndices symmetry =
    case symmetry of
        X ->
            Cardinal
                   1
                1  0  1
                   1
        I ->
            Cardinal
                   2
                1  0  1
                   2
        L ->
            Cardinal
                   2
                1  0  2
                   1
        T ->
            Cardinal
                   2
                1  0  1
                   1
        S -> -- a.k.a `\`
            Cardinal
                   2
                1  0  2
                   1
        A ->
            Cardinal
                   1
                1  0  1
                   0
        Q -> -- a.k.a `\`
            Cardinal
                   1
                2  0  4
                   3
        -}


{-
matchesBySymmetry : Direction -> Symmetry -> Symmetry -> Bool
matchesBySymmetry dir symmetryA symmetryB =
    (Neighbours.getCardinal dir <| symmetryToIndices symmetryA)
    == (Neighbours.getCardinal (Neighbours.opposite dir) <| symmetryToIndices symmetryB)
-}




