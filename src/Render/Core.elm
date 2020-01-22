module Render.Core exposing (..)


import Array

import Html exposing (..)
import Html.Attributes exposing (..)

import WFC.Occurrence as WFC exposing (..)
import WFC.Solver.History exposing (History)
import WFC.Solver.History as History
import WFC.Solver exposing (Step(..), StepStatus(..), FocusState(..))
import WFC.Plane.Impl.Tracing exposing (..)
import WFC.Matches as Matches exposing (..)


type alias Spec v a msg =
    { default : a
    , contradiction : a
    , v : v -> Html msg
    , a : a -> Html msg
    , merge : List a -> a
    , scaled : Float -> a -> Html msg
    , vToString : v -> String
    }


withIndex : Int -> Html msg -> Html msg
withIndex index subView =
    div []
        [ text <| String.fromInt index ++ "."
        , subView
        ]


withCoords : (v -> Html msg) -> (a -> Html msg) -> (v -> a -> Html msg)
withCoords viewV viewA =
    \v a ->
        span
            []
            [ viewV v
            , viewA a
            ]


occursText : WFC.Occurrence -> String
occursText occured =
    case occured of
        Unknown -> "occurs unknown amount of times"
        Times howMuch -> "occurs " ++ String.fromInt howMuch ++ " times"


listBy : (a -> Html msg) -> List a -> Html msg
listBy viewItem items =
    div [ style "display" "flex"
        , style "flex-direction" "row"
        , style "justify-content" "space-evenly"
        ]
        <| List.map viewItem items


history : (a -> Html msg) -> History a -> Html msg
history viewItem theHistory =
    div
        [ style "position" "absolute"
        , style "right" "0"
        , style "margin-top" "-400px"
        , style "display" "flex"
        , style "flex-direction" "column"
        ]
        <| (History.toList theHistory
            |> List.map viewItem)


step : (v -> Html msg) -> Step v -> Html msg
step viewV (Step num _ status) =
    span
        [ style "padding" "0 2px"
        ]
        [ text <| String.fromInt num
        -- , text " "
        -- , text seed
        , text " "
        , case status of
           Initial -> text "(initial)"
           InProgress focus _ ->
            span
                []
                [ text "(in progress"
                , case focus of
                    FocusedAt v ->
                        span
                            []
                            [ text ": "
                            , viewV v
                            ]
                    NotFocused -> text ""
                , text ")" ]
           Solved _ -> text "(solved)"
           Terminated -> text "(terminated)"
           Exceeded attempts -> text <| "(exceeded " ++ String.fromInt attempts ++ ")"
        ]


tracingCell : a -> (a -> Html msg) -> TracingCell a -> Html msg
tracingCell whenNone viewItem ( matches, items ) =
    span
        [ ]
        [ span
            [ style "display" "inline-block"
            , style "width" "100px"
            , style "height" "88px"
            , style "padding-top" "12px"
            , style "overflow" "hidden"
            , style "text-overflow" "ellipsis"
            ]
            [
                Matches.toList matches
                    |> List.map String.fromInt
                    |> String.join "|"
                    |> text
            ]
        , span
            [ style "display" "inline-block"
            , style "width" "100px"
            , style "max-width" "100px"
            , style "height" "100px"
            , style "max-height" "100px"
            , style "overflow" "hidden"
            , style "text-overflow" "ellipsis"
            ]
            <| case List.length items of
                    0 -> [ viewItem whenNone ]
                    _ -> items |> List.map viewItem
        ]