port module Main exposing (main)

import AnimationFrame
import Html exposing (Html, text, div, input, br)
import Html.Attributes as A exposing (width, height, style, type_, min, max, step)
import Html.Events exposing (onInput)
import Task exposing (Task)
import Time exposing (Time)
import Math.Matrix4 as Mat4 exposing (Mat4)
import Math.Vector3 as Vec3 exposing (Vec3, vec3, getX, getY, getZ)
import WebGL exposing (Mesh, Shader, Entity)
import Window


scale : Float
scale = 0.5


type alias LorenzConfig =
    { sigma : Float
    , beta : Float
    , rho : Float
    , stepSize : Float
    , stepsPerFrame : Int
    }


type alias Model =
    { config : LorenzConfig
    , paused : Bool
    , fps : Int
    , theta : Float
    , lorenz : Mesh Vertex
    , numVertices : Int
    }


type alias Vertex =
    { position : Vec3
    , color : Vec3
    }


type Msg
    = Animate Time
    | Resize Window.Size
    | ChangeConfig LorenzConfig
    | AdjustVertices Int
    | Rotate Float
    | Pause
    | Start


init : ( Model, Cmd Msg )
init =
    let
        numVertices = 2000
        lorenzConfig =
            { sigma = 10
            , beta = 8 / 3
            , rho = 28
            , stepSize = 0.005
            , stepsPerFrame = 3
            }
    in
        (
            { config = lorenzConfig
            , paused = False
            , fps = 0
            , theta = 0.1
            , lorenz = lorenzConfig |> lorenz numVertices
            , numVertices = numVertices
            }
        , Cmd.batch
            [ Task.perform Resize Window.size
            ]
        )


lorenz : Int -> LorenzConfig -> Mesh Vertex
lorenz numVertices config =
    let
        x0 = 0.1
        y0 = 0
        z0 = 0
        -- vertices = Debug.log "vertices" (List.range 1 numVertices
        vertices = List.range 1 numVertices
           |> List.foldl (\_ positions ->
                   let
                       len = List.length positions
                       maybePrev = (List.drop (len - 1) positions) |> List.head
                   in
                       case maybePrev of
                           Just prev -> positions ++ [ prev |> step config  ]
                           Nothing -> [ vec3 x0 y0 z0 ]
               ) []
    in
        vertices
            |> List.map triangleAt
            |> WebGL.triangles


step : LorenzConfig -> Vec3 -> Vec3
step config v =
    let
        ( x, y, z ) = ( getX v, getY v, getZ v )
        σ = config.sigma
        β = config.beta
        ρ = config.rho
        -- δt = config.dt / 1000
        δt = config.stepSize
        δx = σ * (y - x) * δt
        δy = ( x * (ρ - z) - y ) * δt
        δz = ( x * y - β * z ) * δt
    in
        vec3 (x + δx) (y + δy) (z + δz)


triangleAt : Vec3 -> ( Vertex, Vertex, Vertex )
triangleAt v =
    let
        x = getX v / 10
        y = getY v / 10
        z = getZ v / 100
        tw = 3 / 400 / scale
        th = 3 / 400 / scale
    in
        ( Vertex (vec3 x (y + th / 2) z) (vec3 1 0 0)
        , Vertex (vec3 (x + tw) (y + th / 2) z) (vec3 0 1 0)
        , Vertex (vec3 (x + tw / 2) (y - th / 2) z) (vec3 0 0 1)
        )


view : Model -> Html Msg
view ({ config, lorenz } as model) =
    div [ ]
        ( text (toString model.fps ++ "FPS")
          :: controls model
          :: WebGL.toHtml
                [ width 800
                , height 800
                , style [ ( "display", "block" ) ]
                ]
                [ WebGL.entity
                    vertexShader
                    fragmentShader
                    model.lorenz
                    { perspective = perspective 1 model.theta }
                ]
          :: []
        )


controls : Model -> Html Msg
controls ({ config, lorenz } as model) =
    div [ ]
        [ input [ type_ "range", A.min "10", A.max "10000", A.step "30"
                , onInput (\iStr ->
                    AdjustVertices (String.toInt iStr
                                    |> Result.withDefault model.numVertices)) ]
                [ ]
        , text ("vertices : " ++ toString model.numVertices)
        , br [] []
        , input [ type_ "range", A.min "0", A.max "1", A.step "0.01"
                , onInput (\fStr ->
                    Rotate (String.toFloat fStr
                            |> Result.withDefault model.theta)) ]
                [ ]
        , text ("theta : " ++ toString model.theta)
        , br [] []
        , input [ type_ "range", A.min "0", A.max "100", A.step "0.1"
                , onInput (\fStr ->
                    ChangeConfig { config
                                    | sigma = String.toFloat fStr
                                            |> Result.withDefault config.sigma
                                    }
                    )
                ]
                [ ]
        , text ("sigma : " ++ toString model.config.sigma)
        , br [] []
        , input [ type_ "range", A.min "0", A.max "15", A.step "0.01"
                , onInput (\fStr ->
                    ChangeConfig { config
                                    | beta = String.toFloat fStr
                                            |> Result.withDefault config.beta
                                    }
                    )
                ]
                [ ]
        , text ("beta : " ++ toString model.config.beta)
        , br [] []
        , input [ type_ "range", A.min "0", A.max "100", A.step "0.5"
                , onInput (\fStr ->
                    ChangeConfig { config
                                    | rho = String.toFloat fStr
                                            |> Result.withDefault config.rho
                                    }
                    )
                ]
                [ ]
        , text ("rho : " ++ toString model.config.rho)
        , br [] []
        , input [ type_ "range", A.min "0", A.max "1", A.step "0.001"
                , onInput (\fStr ->
                    ChangeConfig { config
                                    | stepSize = String.toFloat fStr
                                            |> Result.withDefault config.stepSize
                                    }
                    )
                ]
                [ ]
        , text ("step : " ++ toString model.config.stepSize)
        ]


perspective : Float -> Float -> Mat4
perspective t theta =
--    Mat4.identity
--        |> Mat4.scale3 scale scale scale
--        |> Mat4.rotate theta (vec3 1 0 0)
--        --|> Mat4.translate3 -10 -10 0

    Mat4.mul
        (Mat4.mul
            (Mat4.makePerspective 45 1 0.01 100)
            (Mat4.makeLookAt (vec3 (4 * cos t) 0 (4 * sin t)) (vec3 0 0 0) (vec3 0 1 0)))
        ((Mat4.makeRotate (3 * theta) (vec3 0 1 0)))


--    Mat4.mul
--        (Mat4.mul
--            (Mat4.mul
--                (Mat4.makeRotate (3 * theta) (vec3 0 1 0))
--                (Mat4.makeRotate (2 * theta) (vec3 1 0 0)))
--            (Mat4.makePerspective 45 1 0.01 100))
--        (Mat4.makeLookAt (vec3 (4 * cos t) 0 (4 * sin t)) (vec3 0 0 0) (vec3 0 1 0))


port pause : (() -> msg) -> Sub msg

port start : (() -> msg) -> Sub msg

port rotate : (Float -> msg) -> Sub msg

port modify : (LorenzConfig -> msg) -> Sub msg


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ AnimationFrame.diffs Animate
        , Window.resizes Resize
        , rotate Rotate
        , modify ChangeConfig
        , pause (\_ -> Pause)
        , start (\_ -> Start)
        ]


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Animate dt ->
            ( { model | fps = floor (1000 / dt)  }
            , Cmd.none
            )
        AdjustVertices verticesCount ->
            ( { model
              | numVertices = verticesCount
              , lorenz = model.config
                |> lorenz model.numVertices }
            , Cmd.none
            )
        ChangeConfig newConfig ->
            ( { model
              | config = newConfig
              , lorenz = newConfig
                |> lorenz model.numVertices
              }
            , Cmd.none
            )
        Rotate theta ->
            ( { model | theta = theta  }
            , Cmd.none
            )
        _ -> ( model, Cmd.none )


main : Program Never Model Msg
main =
    Html.program
        { init = init
        , view = view
        , subscriptions = subscriptions
        , update = update
        }

-- Shaders


type alias Uniforms =
    { perspective : Mat4 }


vertexShader : Shader Vertex Uniforms { vcolor : Vec3 }
vertexShader =
    [glsl|
        attribute vec3 position;
        attribute vec3 color;
        uniform mat4 perspective;
        varying vec3 vcolor;
        void main () {
            gl_Position = perspective * vec4(position, 1.0);
            vcolor = color;
        }
    |]


fragmentShader : Shader {} Uniforms { vcolor : Vec3 }
fragmentShader =
    [glsl|
        precision mediump float;
        varying vec3 vcolor;
        void main () {
            gl_FragColor = vec4(vcolor, 1.0);
        }
    |]
