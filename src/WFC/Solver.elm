module WFC.Solver exposing (..)


-- import Array exposing (Array)
import Dict
import Dict exposing (Dict)
import Random

import WFC.Vec2 exposing (..)
import WFC.Matches exposing (Matches)
import WFC.Matches as Matches exposing (..)
import WFC.Occurrence exposing (Occurrence, Frequency, frequencyToFloat)
import WFC.Occurrence as Occurrence
import WFC.Plane exposing (Plane(..), N(..))
import WFC.Plane as Plane exposing (map)
import WFC.Plane.Flat as Plane
    exposing ( Boundary, Symmetry, foldl, coords, equal, sub, findMatches, findAllSubs, findAllSubsAlt, findOccurrence )
import WFC.Plane as CPlane exposing (fromDict, toDict)
import WFC.Plane.Offset exposing (OffsetPlane(..), toOffset)
import WFC.Plane.Offset as OffsetPlane exposing (get)
import WFC.Neighbours as Neighbours exposing (..)
import WFC.Neighbours exposing (Neighbours)
import WFC.Neighbours as Dir exposing (Direction(..))


type alias Options v a =
    { approach : Approach v a
    , outputBoundary : Boundary
    , outputSize : v
    , advanceRule : AdvanceRule
    }


type alias Pattern v a = Plane v a
type alias Wave v = Plane v (Matches PatternId)


type AdvanceRule
    = MaximumAttempts Int
    | AdvanceManually


type Approach v a
    = Overlapping
        { patternSize : N v
        , searchBoundary : Boundary
        , symmetry : Symmetry -- FIXME: use in search
        -- TODO: ground : Int
        }
    | Tiled {- Rules -}


type Step v
    = Step Int Random.Seed (StepStatus v)


type FocusState v
    = NotFocused
    | FocusedAt v


type StepStatus v
    = Initial
    | InProgress (FocusState v) (Wave v)
    | Solved (Wave v)
    | Terminated -- terminated by contradiction
    | Exceeded Int


type alias PatternId = Int


type alias PatternWithStats v a =
    { pattern : Pattern v a
    , frequency : ( Occurrence, Maybe Frequency )
    -- TODO: change `matches` to Neighbours
    , matches : OffsetPlane v (List PatternId)
    }


type alias UniquePatterns v a =
    Dict
        PatternId
        (PatternWithStats v a)


type alias Walker v =
    { first : v
    , next : v -> Direction -> v -- FIXME: swap arguments
    , random : Random.Generator v
    , all : () -> List v
    -- TODO: v -> comparable
    }


-- type alias FindMatches v a =
--     Wave v -> v -> Direction -> Matches a


type Observation v
    = Unknown
    | Collapsed
    | Contradiction
    | Focus v PatternId


type Solver v a =
    Solver
        { source : Plane v a
        , walker : Walker v
        , outputSize : v
        , outputBoundary : Boundary -- FIXME: use in solving
        , advanceRule : AdvanceRule
        , patterns : UniquePatterns v a
            -- FIXME: could be either:
            --        UniquePatterns, pixel by pixel,
            --        or Tiles which are just IDs themselves;
            --        also, could be a function like: Wave v -> v -> Direction -> Matches a
        }


firstStep : Random.Seed -> Step v
firstStep seed =
    Step 0 seed Initial


init
    :  AdvanceRule
    -> UniquePatterns v a
    -> v
    -> Boundary
    -> Walker v
    -> Plane v a
    -> Solver v a
init advanceRule patterns outputSize outputBoundary walker source =
    Solver
        { source = source
        , walker = walker
        , patterns = patterns
        , advanceRule = advanceRule
        , outputSize = outputSize
        , outputBoundary = outputBoundary
        }


solve : Solver v a -> Step v -> Step v
solve (Solver { advanceRule, source, patterns, walker, outputSize } as solver) step  =
    let
        seed = getSeed step
        advance wave =
            case observe seed walker patterns wave of
                ( Collapsed, oSeed ) ->
                    nextStep oSeed step <| Solved wave
                ( Contradiction, oSeed ) ->
                    nextStep oSeed step <| Terminated
                ( Unknown, oSeed ) ->
                    nextStep oSeed step <| Terminated
                ( Focus position pattern, oSeed ) ->
                    case propagate oSeed patterns walker position pattern wave of
                        ( newWave, pSeed ) ->
                            let
                                next =
                                    nextStep pSeed step
                                        <| InProgress (FocusedAt position) newWave
                            in case advanceRule of
                                AdvanceManually -> next
                                MaximumAttempts maxAttempts ->
                                    if not (step |> exceeds maxAttempts)
                                    then next |> solve solver
                                    else next |> (updateStatus <| Exceeded maxAttempts)
    in
        case getStatus step of
            Initial ->
                -- advance <| initWave patterns source
                initWave patterns outputSize
                    |> InProgress NotFocused
                    |> nextStep seed step
            InProgress _ wave ->
                advance wave
            _ -> step


observe
    :  Random.Seed
    -> Walker v
    -> UniquePatterns v a
    -> Wave v
    -> ( Observation v, Random.Seed )
observe seed walker uniquePatterns wave =
    if wave |> hasAContradiction walker then
        ( Contradiction, seed )
    else if wave |> isWaveCollapsed walker then
        ( Collapsed, seed )
    else
        let
            ( result, eSeed ) =
                wave |> findLowestEntropy seed uniquePatterns walker
            ( coord, cSeed ) =
                case result of
                    Just c -> ( c, eSeed )
                    Nothing ->
                        Random.step walker.random eSeed
        in
            Plane.get coord wave
                |> Maybe.andThen
                    (
                        Matches.run
                            (always Nothing)
                            (\first tail ->
                                let
                                    patternChoiceGenerator =
                                        randomPattern uniquePatterns first tail
                                in
                                    Random.step patternChoiceGenerator cSeed
                                        |> Tuple.mapFirst (Focus coord)
                                        |> Just
                            )
                    )
                |> Maybe.withDefault ( Contradiction, cSeed )

propagate
    :  Random.Seed
    -> UniquePatterns v a
    -> Walker v
    -> v
    -> PatternId
    -> Wave v
    -> ( Wave v, Random.Seed )
propagate seed uniquePatterns walker focus pattern (Plane waveSize waveF as wave) =
    let
        _ = Debug.log "focus" focus
        _ = Debug.log "pattern" pattern
        matchesLeft =
            wave
                |> Plane.get focus
                |> Maybe.map (Matches.exclude pattern >> Matches.toList)
                |> Maybe.withDefault []
        ban : v -> PatternId -> Wave v -> Wave v
        ban pos otherPattern w =
            w |> Plane.adjustAt (Matches.exclude otherPattern) pos
        patternsMatchingAtDir : PatternId -> Direction -> Matches PatternId
        patternsMatchingAtDir otherPattern dir =
            getMatchesOf walker uniquePatterns dir otherPattern
                |> Maybe.withDefault Matches.none
        -- rebuild : Wave v -> Wave v
        -- rebuild w =
        --     CPlane.toDict (walker.all ()) w |> CPlane.fromDict
        forget : v -> PatternId -> Wave v -> Wave v
        forget banPos banPattern w =
            [ Dir.N, Dir.W, Dir.S, Dir.E ]
                |> List.foldl
                    (\dir prevWave ->
                        let
                            movedPos =
                                dir
                                    |> Debug.log "dir"
                                    |> walker.next banPos
                                    |> Debug.log "movedPos"
                            curMatches =
                                Plane.get banPos w
                                    |> Maybe.withDefault Matches.none
                                    |> Debug.log "curMatches"
                            nextWave =
                                prevWave
                                    |> ban banPos banPattern
                            matchesAtDir =
                                dir
                                    |> patternsMatchingAtDir banPattern
                                    |> Debug.log "macthesAtDir"
                        in
                            matchesAtDir
                                |> Matches.toList
                                |> List.foldl
                                    (\otherPattern ww ->
                                        let
                                            oppositeMatches =
                                                Neighbours.opposite dir
                                                    |> patternsMatchingAtDir otherPattern
                                                    |> Debug.log "oppositeMatches"
                                            otherMatchesLeft =
                                                Plane.get banPos ww
                                                    |> Maybe.withDefault Matches.none
                                                    |> Debug.log "otherMatchesLeft"
                                        in
                                            if Matches.and oppositeMatches otherMatchesLeft
                                                |> Debug.log "and"
                                                |> Matches.isNone
                                                |> Debug.log "isNone"
                                            then
                                                ww
                                                    |> ban movedPos otherPattern
                                                    -- |> forget otherPos otherPattern
                                            else ww
                                    )
                                    nextWave
                    )
                    w
        foldForget : List (v, PatternId) -> Wave v -> Wave v
        foldForget banlist w =
            banlist
                |> List.foldl
                    (\(banPos, panPattern) -> forget banPos panPattern) -- uncurry
                    w
    in
        ( wave
            |> foldForget ( matchesLeft |> List.map (Tuple.pair focus) |> Debug.log "matchesLeft" )
        , seed
        )


noiseCoefficient : Float
noiseCoefficient = 0.1


entropyOf : Random.Seed -> UniquePatterns v a -> Matches PatternId -> ( Maybe Float, Random.Seed )
entropyOf seed uniquePatterns matches =
    case Matches.count matches of
        0 -> ( Nothing, seed ) -- contradiction
        1 -> ( Just 0, seed )
        count ->
            let
                patternFrequency : PatternId -> Maybe Frequency
                patternFrequency patternId =
                    Dict.get patternId uniquePatterns |>
                        Maybe.map .frequency |>
                        Maybe.andThen Tuple.second
                -- TODO: prepare frequency lists in advance, before calculation
                weights =
                    matches
                        |> Matches.toList
                        |> List.map patternFrequency
                        |> List.filterMap identity
                        |> List.map frequencyToFloat
                maxWeight =
                    List.maximum weights |> Maybe.withDefault 0
                sumOfWeights = List.foldl (+) 0 weights
                sumOfLoggedWeights =
                    weights
                        |> List.map (logBase 2)
                        |> List.foldl (+) 0
                pureEntropy =
                    (logBase 2 sumOfWeights) - (sumOfLoggedWeights / sumOfWeights)
            in
                Random.step (Random.float 0 <| maxWeight * noiseCoefficient) seed
                    |> Tuple.mapFirst ((+) pureEntropy >> Just)


findLowestEntropy
    :  Random.Seed
    -> UniquePatterns v a
    -> Walker v
    -> Wave v
    -> ( Maybe v, Random.Seed )
findLowestEntropy seed uniquePatterns { all } (Plane _ waveF) =
    let
        withEntropy prevSeed matches f =
            matches
                |> entropyOf prevSeed uniquePatterns
                |> Tuple.mapFirst (Maybe.andThen f)
        foldingF curCoord ( maybePrevLowest, prevSeed ) =
            case ( waveF curCoord, maybePrevLowest ) of
                ( Nothing, _ ) ->
                    ( maybePrevLowest, prevSeed )
                ( Just matches, Nothing ) ->
                    withEntropy prevSeed matches
                        <| \curEntropy ->
                            if curEntropy > 0
                            then Just ( curCoord, curEntropy )
                            else maybePrevLowest
                ( Just matches, Just ( _, prevMinEntropy ) ) ->
                    withEntropy prevSeed matches
                        <| \curEntropy ->
                            if curEntropy > 0 && curEntropy < prevMinEntropy
                            then Just ( curCoord, curEntropy )
                            else maybePrevLowest
    in
        List.foldl
            foldingF
            ( Nothing, seed )
            ( all () )
            |> Tuple.mapFirst (Maybe.map Tuple.first)
                -- FIXME: if Walker will be the part of every Plane
                -- , then we won't need to pass it inside and just use
                -- Walker's folding mechanics


 -- TODO: produce several IDs?
randomPattern : UniquePatterns v a -> PatternId -> List PatternId -> Random.Generator PatternId
randomPattern uniquePatterns first others =
    let
        packWithFrequency : PatternId -> ( Float, PatternId )
        packWithFrequency pattern =
            ( uniquePatterns
                |> Dict.get pattern
                |> Maybe.andThen (.frequency >> Tuple.second)
                |> Maybe.map frequencyToFloat
                |> Maybe.withDefault 0
            , pattern
            )
    in
        Random.weighted
            (packWithFrequency first)
            (others |> List.map packWithFrequency)


getMatchesOf : Walker v -> UniquePatterns v a -> Direction -> PatternId -> Maybe (Matches PatternId)
getMatchesOf walker uniquePatterns dir pattern =
    uniquePatterns
        |> Dict.get pattern
        |> Maybe.andThen
            (\{ matches } ->
                let
                    movedPos = walker.next walker.first dir
                in
                    matches
                        |> OffsetPlane.get (movedPos |> toOffset)
            )
        |> Maybe.map Matches.fromList


 -- FIXME: Maybe Bool
hasAContradiction : Walker v -> Wave v -> Bool
hasAContradiction { all } (Plane _ waveF) =
    List.foldl
        (\coord wasAContradiction ->
            wasAContradiction ||
                (waveF coord
                    |> Maybe.map Matches.isNone
                    |> Maybe.withDefault True)
        )
        False
        ( all () )


 -- FIXME: Maybe Bool
isWaveCollapsed : Walker v -> Wave v -> Bool
isWaveCollapsed { all } (Plane _ waveF) =
    List.foldl
        (\coord wasCollapsed ->
            wasCollapsed &&
                (waveF coord
                    |> Maybe.map (\matches -> Matches.count matches == 1)
                    |> Maybe.withDefault False)
        )
        True
        ( all () )


loadFrequencies : UniquePatterns v a -> Dict PatternId (Maybe Frequency)
loadFrequencies = Dict.map <| always <| (.frequency >> Tuple.second)


initWave : UniquePatterns v a -> v -> Wave v
initWave uniquePatterns size =
    -- Dict.keys uniquePatterns >> Matches.fromList >> Plane.filled
    Plane.filled size <| Matches.fromList <| Dict.keys uniquePatterns


apply
    :  (Matches PatternId -> List a -> x)
    -> Solver v a
    -> Step v
    -> Plane v x
apply f (Solver { patterns, walker, source, outputSize }) (Step _ _ status) =
    let
        loadValues : Matches PatternId -> List a
        loadValues matches =
            matches
                |> Matches.toList
                |> List.map (\patternId ->
                    patterns
                        |> Dict.get patternId
                        |> Maybe.andThen (\p -> Plane.get walker.first p.pattern)
                    )
                |> List.filterMap identity
                -- if pattern wasn't found or contains no value at this point, it is skipped
        fromWave : Wave v -> Plane v x
        fromWave wave = wave |> Plane.map (\matches -> f matches <| loadValues matches)
    in
        fromWave <| case status of
            Initial -> initWave patterns outputSize
            InProgress _ wave -> wave
            Solved wave -> wave
            Terminated -> Plane.empty outputSize
            Exceeded _ -> Plane.empty outputSize


getSource : Solver v a -> Plane v a
getSource (Solver { source }) = source


getUniquePatterns : Solver v a -> UniquePatterns v a
getUniquePatterns (Solver { patterns }) = patterns


getWalker : Solver v a -> Walker v
getWalker (Solver { walker }) = walker


getSeed : Step v -> Random.Seed
getSeed (Step _ seed _) = seed


changeSeedTo : Random.Seed -> Step v -> Step v
changeSeedTo newSeed (Step n seed step) = Step n newSeed step


getStatus : Step v -> StepStatus v
getStatus (Step _ _ status) = status


getCount : Step v -> Int
getCount (Step n _ _) = n


nextStep : Random.Seed -> Step v -> StepStatus v -> Step v
nextStep seed (Step n _ _) status = Step (n + 1) seed status


updateStatus : StepStatus v -> Step v -> Step v
updateStatus status (Step n seed _) = Step n seed status


exceeds : Int -> Step v -> Bool
exceeds count (Step stepN _ _) = count <= stepN


{-
neighboursAt : Direction -> List (PatternId, Pattern v a) -> Pattern v a -> List PatternId
neighboursAt dir from (Pattern size f) =
    []


findNeighbours : List (PatternId, Pattern v a) -> Pattern v a -> Neighbours (List PatternId)
findNeighbours from pattern =
    Neighbours
        (neighboursAt NW from pattern) (neighboursAt N from pattern) (neighboursAt NE from pattern)
        (neighboursAt W  from pattern)                               (neighboursAt  E from pattern)
        (neighboursAt SW from pattern) (neighboursAt S from pattern) (neighboursAt SE from pattern)
-}
