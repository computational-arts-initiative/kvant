module Kvant.Plane exposing (..)


import Array exposing (Array)
import Dict
import Dict exposing (Dict)

import Kvant.Vec2 exposing (Vec2)
import Kvant.Vec2 as Vec2 exposing (rect)
import Kvant.Neighbours exposing (Neighbours)
import Kvant.Neighbours as Neighbours exposing (..)


type Plane a = Plane ( Vec2, Vec2 ) (Array (Array a))


map : (a -> b) -> Plane a -> Plane b
map f (Plane size  grid) =
    Plane size <| Array.map (Array.map f) <| grid


positionedMap : (Vec2 -> a -> b) -> Plane a -> Plane b
positionedMap f (Plane size grid) =
    Plane size <|
        (grid
            |> Array.indexedMap
                (\y row ->
                    row |> Array.indexedMap (\x v -> f (x, y) v)
                )
        )


empty : Vec2 -> Plane a
empty size = Plane ( (0, 0), size ) Array.empty


get : Vec2 -> Plane a -> Maybe a
get (x, y) (Plane ( ( ox, oy ), (w, h) ) grid) =
    if x >= ox + w || y >= oy + h then Nothing
    else if x < ox || y < oy then Nothing
    else
        grid
            |> Array.get y
            |> Maybe.andThen (Array.get x)


set : Vec2 -> a -> Plane a -> Plane a
set (x, y) value (Plane ( ( ox, oy ), (w, h) ) grid) =
    Plane ( ( ox, oy ), (w, h) )
        <| if x >= ox + w || y >= oy + h then grid
           else if x < ox || y < oy then grid
           else
                let
                    maybeRow = grid |> Array.get y
                in case maybeRow of
                    Just row ->
                        grid |> Array.set y (row |> Array.set x value)
                    Nothing -> grid


getOrigin : Plane a -> Vec2
getOrigin (Plane ( origin, _ ) _) = origin


getSize : Plane a -> Vec2
getSize (Plane ( _, size ) _) = size


filled : Vec2 -> a -> Plane a
filled (w, h) v =
    Plane ( ( 0, 0 ), (w, h) )
        <| Array.repeat h
        <| Array.repeat w v


equalAt : List Vec2 -> (a -> a -> Bool) -> Plane a -> Plane a -> Bool
equalAt atCoords compareF planeA planeB =
    atCoords
        |> List.foldl
            (\coord before ->
                before &&
                    ( case ( planeA |> get coord, planeB |> get coord) of
                        ( Just valueA, Just valueB )
                            -> compareF valueA valueB
                        _ -> False
                    )
            )
            True


setAll : List (Vec2, a) -> Plane a -> Plane a
setAll values start =
    List.foldl
        (\(v, a) plane -> plane |> set v a)
        start
        values


fromList : Vec2 -> List (Vec2, a) -> Plane (Maybe a)
fromList size list =
    filled size Nothing
        |> setAll (list |> List.map (Tuple.mapSecond Just))


coords : Plane a -> List (List Vec2)
coords (Plane ( origin, size ) _) =
    Vec2.rect { from = origin, to = size }


all : Plane a -> List a
all (Plane _ grid) =
    grid
        |> Array.map Array.toList
        |> Array.toList
        |> List.concat


allWithCoords : Plane a -> List (Vec2, a)
allWithCoords (Plane ( (ox, oy), _ ) grid) = -- zip all + coords ?
    grid
        |> Array.indexedMap
            (\y row ->
                row
                    |> Array.indexedMap (\x v -> ( ( ox + x, oy + y ), v ) )
                    |> Array.toList
            )
        |> Array.toList
        |> List.concat



{- fromDict : Vec2 -> Dict Vec2 a -> Plane (Maybe a)
fromDict size dict =
    Plane size <| \v -> Dict.get v dict -}


-- TODO: When Walker will be inside the Panel, we may use `Walker.all` for that purpose

{-}
take : List Vec2 -> Plane a -> List (Vec2, Maybe a)
take all (Plane _ f) =
    all |> List.map (\v -> (v, f v))


takeAsDict : List Vec2 -> Plane a -> Dict Vec2 a
takeAsDict all =
    toList all
        >> List.map cellToMaybe
        >> List.filterMap identity
        >> Dict.fromList -}


{- loadNeighbours : Vec2 -> (Vec2 -> Direction -> Vec2) -> Plane a -> Neighbours (Maybe a)
loadNeighbours focus move (Plane _ f) =
    Neighbours.collect focus move f -}


{- apply : Vec2 -> (Vec2 -> Direction -> Vec2) -> Neighbours a -> Plane a -> Plane a
apply focus move neighbours =
    let
        fromNeighbours = neighbours |> Neighbours.byCoord focus move
    in
        positionedMap
            (\v cur ->
                fromNeighbours v
                    |> Maybe.map Just
                    |> Maybe.withDefault cur
            ) -}
