port module Worker exposing (..)

import Random
import Array exposing (Array)

import Kvant.Vec2 exposing (Vec2)
import Kvant.Core exposing (TracingWfc)


type alias StepResult = Array (Array (Array Int))
type alias RunResult = Array (Array Int)


type alias Options = -- TODO
    {

    }


type alias Model = Maybe ( Random.Seed, TracingWfc Vec2 Int )


type Msg
    = Run
    | Step
    | StepBack
    | Stop


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model = ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ run <| always Run
        , step <| always Step
        ]


main : Program () Model Msg
main =
    Platform.worker
        { init = always ( Nothing, Cmd.none )
        , update = update
        , subscriptions = subscriptions
        }


port run : (() -> msg) -> Sub msg

port step : (() -> msg) -> Sub msg

port onResult : RunResult -> Cmd msg

port onStep : StepResult -> Cmd msg

-- TODO: getTiles:

-- TODO: getNeighbours