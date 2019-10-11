module Model.Layer.Def exposing (..)

import Gui.Def exposing (Nest)

import Json.Decode as D
import Json.Encode as E

import Model.Layer.Blend.WebGL as WebGL

import Model.Layer.Context exposing (Context)


type alias DefId = String

type Index = Index Int
type alias JsIndex = Int -- index for ports


type Kind
    = Html
    | WebGL
    | Canvas
    | JS


type alias Def model view msg blend =
    { id : DefId
    , kind : Kind
    , init : Index -> Context -> ( model, Cmd msg )
    , encode : Context -> model -> E.Value
    , decode : Context -> D.Decoder model
    , update : Index -> Context -> msg -> model -> ( model, Cmd msg )
    , view : Index -> Context -> Maybe blend -> model -> view
    , subscribe : Context -> model -> Sub ( Index, msg )
    , gui : Maybe (Index -> model -> Nest msg)
    }


unit : Def () () () ()
unit =
    { id = "unit"
    , kind = JS
    , init = \_ _ -> ( (), Cmd.none )
    , encode = \_ _ -> E.object []
    , decode = always <| D.succeed ()
    , update = \_ _ _ model -> ( model, Cmd.none )
    , view = \_ _ _ _ -> ()
    , subscribe = \_ _ -> Sub.none
    , gui = Nothing
    }


-- kinda Either, but for ports:
--    ( Just WebGLBlend, Nothing ) --> WebGL Blend
--    ( Nothing, Just String ) --> HTML Blend
--    ( Nothing, Nothing ) --> None
--    ( Just WebGLBlend, Just String ) --> ¯\_(ツ)_/¯
type alias PortBlend =
    ( Maybe WebGL.Blend, Maybe String )


type alias PortDef = -- FIXME: actually it's not `PortDef`, but `PortLayer`
    { def : String
    , kind : String
    , blend : PortBlend
    , visible : String
    , opacity : Float
    , zOrder : Int
    , index : Int
    , isOn : Bool
    , model : String
    }


indexToString : Index -> String
indexToString (Index index) = String.fromInt index
