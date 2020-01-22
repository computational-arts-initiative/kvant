module Render.Example.Image exposing (..)

import Image exposing (Image)

import Render.Example exposing (ImageExample, Status(..))
import Render.Example as Example exposing (make)

import WFC.Vec2 exposing (..)
import WFC.Plane exposing (Cell, N(..))
import WFC.Plane.Flat exposing (SearchMethod(..))
import WFC.Core as WFC exposing (..)
import WFC.Solver exposing (Approach(..))
import WFC.Solver as WFC exposing (Step(..), Options)
import WFC.Plane.Impl.Image as ImagePlane exposing (make)


options : WFC.Options Vec2
options =
    { approach = Overlapping
    , patternSearch = Bounded -- Periodic
    , patternSize = N ( 2, 2 )
    , inputSize = ( 4, 4 )
    , outputSize = ( 10, 10 )
    -- , advanceRule = WFC.MaximumAttempts 50
    , advanceRule = WFC.AdvanceManually
    }


quick : Image -> Vec2 -> ImageExample
quick image size =
    Example.make
        (WFC.image options image)
        (WFC.imageTracing options image)
        options
        image
        (ImagePlane.make size)