module WFC.Core exposing
    ( WFC, Instance(..)
    , text, TextWFC
    , run
    )


import Random


import WFC.Vec2 exposing (..)
import WFC.Plane.Text as TextPlane exposing (make, toString)
import WFC.Solver as Solver exposing (initFlat, Step(..), findUniquePatterns)


type WFC v fmt a =
    WFC ( (Solver.Step a, fmt) -> (Solver.Step a, fmt) )


type Instance
    = Text TextWFC


type alias TextWFC = WFC Vec2 String Char


text : Solver.TextOptions -> TextWFC
text options =
    WFC <|
        \(step, input) ->
            let
                -- plane : TextPlane
                plane = input |> TextPlane.make options.inputSize
                -- solver : TextSolver
                solver = Solver.initFlat plane options
            in
                solver
                    |> Solver.solve step
                    |> Tuple.mapSecond TextPlane.toString


-- load : Instance -> WFC pos size fmt item
-- load instance =
--     case instance of
--         Text wfc -> wfc


run : Random.Seed -> fmt -> WFC v fmt a -> fmt
run seed input (WFC wfc) = Tuple.second <| wfc ( Solver.Step 0 seed, input )
