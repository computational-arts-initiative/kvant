port module Worker exposing (..)

import Random
import Task
import Time
import Array exposing (Array)
import Json.Decode as D
import Json.Encode as E

import Kvant.Vec2 as Vec2
import Kvant.Vec2 exposing (Vec2)
import Kvant.Core exposing (Wfc)
import Kvant.Core as Wfc
import Kvant.Solver as Solver
import Kvant.Solver.Options as Options
import Kvant.Plane exposing (..)
import Kvant.Json.Options as Options
import Kvant.Json.Patterns as Patterns
import Kvant.Json.Matches as Matches
import Kvant.Patterns as Patterns
import Kvant.Neighbours exposing (Neighbours)
import Kvant.Neighbours as Neighbours
import Kvant.Matches as Matches
import Kvant.Adjacency as A


type alias Adjacency = A.Adjacency Int Int


type alias Source = Array (Array Int)

type alias StepResult = Array (Array (Array Int))
type alias RunResult = StepResult


{- type Proceed
    = Manually
    | AutoUntil Int -}


type Model
    = Empty
    | Solution StepResult
    | Tracing Wfc Solver.Step -- ( History Vec2 )


type Msg
    = Run Options.Output Adjacency
    | RunWith Options.Output Adjacency Random.Seed
    | Trace Options.Output Adjacency
    | TraceWith Options.Output Adjacency Random.Seed
    | Step
    | StepBack
    | StepBackWith Random.Seed
    | Stop
    | Preprocess Options.Overlapping Adjacency
    | GetMatchesAt Vec2
    | InformError String


defaultOptions : Solver.Options
defaultOptions =
    { approach =
        Overlapping
            { patternSize = (2, 2)
            , inputBoundary = Bounded
            , symmetry = NoSymmetry
            }
    , outputBoundary = Bounded
    , outputSize = ( 10, 10 )
    }


-- TODO: remove
fromPlane : Plane (List Int) -> Array (Array (Array Int))
fromPlane =
    toArray2d
        >> Array.map (Array.map (Maybe.withDefault [] >> Array.fromList))


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Run options adjacency ->
            ( Empty
            , makeSeedAnd <| RunWith options adjacency
            )

        RunWith options adjacency seed ->
            let
                sourcePlane =
                    source
                        |> fromArray2d
                            (Vec2.loadSize source |> Maybe.withDefault (0, 0))
                solution =
                    Wfc.make options sourcePlane
                        |> Wfc.run seed
                        |> fromPlane
            in
                ( Solution solution
                , onResult solution
                )

        Trace options adjacency ->
            ( Empty
            , makeSeedAnd <| TraceWith options adjacency
            )

        TraceWith options adjacency seed ->
            let
                sourcePlane =
                    source
                        |> fromArray2d
                            (Vec2.loadSize source |> Maybe.withDefault (0, 0))
                tracingWfc =
                    Wfc.makeAdvancing options sourcePlane
                ( nextStep, traceResult ) =
                    tracingWfc
                        |> Wfc.firstStep seed
                        --|> Tuple.mapSecond fromPlane
            in
                ( Tracing tracingWfc nextStep
                , onStep <| fromPlane traceResult
                )

        Step ->
            case model of
                Tracing tracingWfc prevStep ->
                    let
                        ( nextStep, traceResult )
                            = tracingWfc
                                |> Wfc.step prevStep
                    in
                        ( Tracing tracingWfc nextStep
                        , onStep <| fromPlane traceResult
                        )
                    -- history |>
                    --             H.push ( lastStep, TracingStep lastTracingStep )
                _ -> ( model, Cmd.none )

        StepBack ->
            ( model
            , makeSeedAnd StepBackWith
            )

        StepBackWith newSeed ->
            {-
            ( case model.status of
                    Solving ( prevResult, prevTracingResult) history ->
                        -- TODO: Will be integrated into the Solver
                        let
                            -- we need to remove two last steps from the history
                            -- to re-run it again from the start and then repeat
                            -- the step which was before the latest, to know
                            -- which result was there at this point
                            historyAStepBack = history |> H.back |> H.back
                            (lastStep, result) =
                                model.wfc
                                    |> Tuple.first
                                    |> Wfc.stepAtOnce
                                        (H.toList historyAStepBack
                                            |> List.map Tuple.first)
                                    |> Maybe.withDefault
                                        (H.last history
                                            |> Tuple.first
                                            |> \s -> ( s, prevResult ))
                            (lastTracingStep, tracingResult) =
                                model.wfc
                                    |> Tuple.second
                                    |> Wfc.stepAtOnce
                                        (H.toList historyAStepBack
                                            |> List.map Tuple.second
                                            |> List.map (\(TracingStep s) -> s))
                                    |> Maybe.withDefault
                                        (H.last history
                                            |> Tuple.second
                                            |> (\(TracingStep s) -> s)
                                            |> \s -> ( s, prevTracingResult ))
                            nextHistory =
                                historyAStepBack |>
                                    H.push
                                        ( lastStep |> Solver.changeSeedTo newSeed
                                        , TracingStep
                                            (lastTracingStep |> Solver.changeSeedTo newSeed)
                                        )
                        in
                            { model
                            | status =
                                Solving
                                    ( result, tracingResult )
                                    nextHistory
                            }
                    _ -> model
            -}
            ( model
            , Cmd.none
            )

        Stop ->
            ( Empty
            , Cmd.none
            )

        Preprocess options source ->
            ( model
            , case options.approach of
                Overlapping overlappingOptions ->
                    let
                        sourcePlane =
                            source
                                |> fromArray2d
                                    (Vec2.loadSize source |> Maybe.withDefault (0, 0))
                    in
                    sourcePlane
                        |> Patterns.preprocess
                            overlappingOptions.symmetry
                            overlappingOptions.inputBoundary
                            overlappingOptions.patternSize
                        |> Patterns.encode
                        |> onPatterns
                Tiled ->
                    Cmd.none
            )

        GetMatchesAt position ->
            ( model
            , onMatches <| Matches.encodeNeighbours <| case model of
                Tracing _ step_ ->
                    step_ |> Solver.extractMatchesAt position
                        |> Maybe.withDefault (Neighbours.fill Matches.none)
                _ -> Neighbours.fill Matches.none
            )

        InformError error ->
            ( Empty
            , onError error
            )


{-
type Command a = Command String (D.Decoder a)
type CommandResponse a = CommandResponse String (a -> E.Value)
-}



subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ run <| \{options, adjacency} ->
            case options |> D.decodeValue Options.decode of
                Ok decodedOptions -> Run decodedOptions adjacency
                Err _ -> Run defaultOptions adjacency -- FIXME: show error

        , trace <| \{options, adjacency} ->
            case options |> D.decodeValue Options.decode of
                Ok decodedOptions -> Trace decodedOptions adjacency
                Err _ -> Trace defaultOptions adjacency -- FIXME: show error
        , step <| always Step
        , back <| always StepBack
        , stop <| always Stop
        , preprocess <| \{options, adjacency} ->
            case options |> D.decodeValue Options.decode of
                Ok decodedOptions -> Preprocess decodedOptions adjacency
                Err error -> InformError <| D.errorToString error
        , matchesAt GetMatchesAt
        ]


main : Program () Model Msg
main =
    Platform.worker
        { init = always ( Empty, Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }


makeSeedAnd : (Random.Seed -> msg) -> Cmd msg
makeSeedAnd makeMsg =
    Task.perform
        (\time ->
            makeMsg <| Random.initialSeed <| Time.posixToMillis time
        )
        Time.now


{-
port execute : ({ cmd : String, payload : E.Value } -> msg) -> Sub msg

port respond : { cmd : String, payload : E.Value } -> Cmd msg
-}


{- FIXME: remove -}
port run : ({ options : E.Value, adjacency : E.Value } -> msg) -> Sub msg

port stop : (() -> msg) -> Sub msg

port trace : ({ options : E.Value, adjacency : E.Value } -> msg) -> Sub msg

port step : (() -> msg) -> Sub msg

port back : (() -> msg) -> Sub msg

port preprocess : ({ options : E.Value, source : Source } -> msg) -> Sub msg

port matchesAt : (( Int, Int ) -> msg) -> Sub msg

port onResult : RunResult -> Cmd msg

port onStep : StepResult -> Cmd msg

port onPatterns : E.Value -> Cmd msg

port onMatches : E.Value -> Cmd msg
{- FIXME: remove -}

port onError : String -> Cmd msg

