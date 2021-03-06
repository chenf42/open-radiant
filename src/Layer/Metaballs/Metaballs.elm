module Layer.Metaballs.Metaballs exposing
    ( Model
    , init
    , view
    , generate
    , generator
    )

import Viewport exposing (Viewport)

import Math.Vector2 as V2 exposing (..)
import Math.Vector3 as V3 exposing (..)
import Array
import Random
import Html exposing (Html)
import Svg as S exposing (..)
import Svg.Attributes as SA exposing (..)

import Model.Product as Product


type Msg = Rebuild Model


-- v = 0.5
handleLenRate = 2.5
distanceFactor = 1.5
globalMaxDistance = 2000
circlesFill = "black"
loop = 4000.0
product = Product.PyCharm


type Tween =
    Translate
        { from: Vec2
        , to: Vec2
        , start: Float
        , end: Float
        }


type alias GroupSource =
    { gradientCenter: Vec2
    , opacity: Float
    , circles: List ( Vec2, Float )
    }


type alias Model =
    { colors: Product.Palette
    , groups: List GroupSource
    }


type alias ModelGenerator = Random.Generator Model


type Color = Color String


type alias Transform = Vec2


type alias Circle =
    { origin : Vec2
    , radius: Float
    , tweens: List Tween
    , transform: Transform
    }


type alias Connection =
    { p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2
    , h1: Vec2, h2: Vec2, h3: Vec2, h4: Vec2
    , escaped: Bool
    , radius: Float
    , builtFrom: ( Circle, Circle )
    }


type alias Path = String


type ConnectionView
    = NoConnection
    | ConnectionView ( List ( Path, Color ) )


type Scene = Scene (List Group)


type Group =
    Group
        { circles : List Circle
        , connections: List ( Path, Color )
        , opacity: Float
        }


type alias Segment =
    { point : Vec2
    , handleIn : Maybe Vec2
    , handleOut : Maybe Vec2
    }


init : Model
init =
    { colors = Product.transparentPalette
    , groups = []
    }


minGroups = 2
maxGroups = 3
minNumberOfCircles = 5
maxNumberOfCircles = 30
minRadius = 20
maxRadius = 200
minOpacity = 0.4
maxOpacity = 1


generator : Product.Palette -> ( Int, Int ) -> Random.Generator Model
generator palette ( w, h ) =
    let
        generatePosition =
            Random.map2 V2.vec2
                (Random.float 0 <| toFloat w)
                (Random.float 0 <| toFloat h)
        generateRadius = Random.float minRadius maxRadius
        generateCircles =
            Random.int minNumberOfCircles maxNumberOfCircles
                        |> Random.andThen
                            (\numCircles ->
                                Random.pair generatePosition generateRadius
                                    |> Random.list numCircles
                            )
    in
        Random.int minGroups maxGroups
            |> Random.andThen
                (\numGroups ->
                    Random.map3 GroupSource
                        generatePosition
                        (Random.float minOpacity maxOpacity)
                        generateCircles
                    |> Random.list numGroups
                )
            |> Random.map (Model palette)



generate : (Model -> msg) -> Random.Generator Model -> Cmd msg
generate = Random.generate


circle : ( Float, Float ) -> Float -> List Tween -> Circle
circle ( x, y ) r tweens = Circle (vec2 x y) r tweens (vec2 0 0)


translate : ( Float, Float ) -> ( Float, Float ) -> Float -> Float -> Tween
translate ( x0, y0 ) ( x1, y1 ) start end =
    Translate { from = (vec2 x0 y0), to = (vec2 x1 y1), start = start, end = end }


buildPath : Connection -> Path
buildPath { p1, p2, p3, p4, h1, h2, h3, h4, escaped, radius } =
    let
        vecstr vec = String.fromFloat (V2.getX vec) ++ "," ++ String.fromFloat (V2.getY vec)
    in
        String.join " "
            [ "M", vecstr p1
            , "C", vecstr h1, vecstr h3, vecstr p3
            , "A", String.fromFloat radius, String.fromFloat radius
                 , "0", if escaped then "1" else "0", "0", vecstr p4
            , "C", vecstr h4, vecstr h2, vecstr p2
            ]


connect : Circle -> Circle -> ConnectionView
connect circle1 circle2 =
    let
        vecAt center a r =
            let ( cx, cy ) = ( V2.getX center, V2.getY center )
            in
                vec2
                    (cx + r * cos a)
                    (cy + r * sin a)
        angleBetween vec1 vec2 =
            atan2 (V2.getY vec1 - V2.getY vec2) (V2.getX vec1 - V2.getX vec2)
        center1 = V2.add circle1.origin circle1.transform
        center2 = V2.add circle2.origin circle2.transform
        radius1 = circle1.radius
        radius2 = circle2.radius
        maxDistance = Basics.min (radius1 + radius2 * distanceFactor) globalMaxDistance
        -- maxDistance = radius1 + radius2
        halfPi = pi / 2
        d = V2.distance center1 center2
        v = 0.4
    in
        -- No blob if a radius is 0
        -- or if distance between the circles is larger than max-dist
        -- or if circle2 is completely inside circle1
        if (radius1 <= 0 || radius2 <= 0) then
            NoConnection
        else if (d > maxDistance || d <= abs (radius1 - radius2)) then
            NoConnection
        else
            let
                circlesOverlap = d < (radius1 + radius2)

                -- Calculate u1 and u2 if the circles are overlapping
                u1 =
                    if circlesOverlap then
                        acos <| (radius1 * radius1 + d * d - radius2 * radius2) / (2 * radius1 * d)
                    else 0
                u2 =
                    if circlesOverlap then
                        acos <| (radius2 * radius2 + d * d - radius1 * radius1) / (2 * radius2 * d)
                    else 0

                -- Calculate the max spread
                angleBetweenCenters = angleBetween center2 center1
                maxSpread = acos <| (radius1 - radius2) / d

                -- Angles for the points
                angle1 = angleBetweenCenters + u1 + (maxSpread - u1) * v
                angle2 = angleBetweenCenters - u1 - (maxSpread - u1) * v
                angle3 = angleBetweenCenters + pi - u2 - (pi - u2 - maxSpread) * v
                angle4 = angleBetweenCenters - pi + u2 + (pi - u2 - maxSpread) * v

                -- Point locations
                p1 = vecAt center1 angle1 radius1
                p2 = vecAt center1 angle2 radius1
                p3 = vecAt center2 angle3 radius2
                p4 = vecAt center2 angle4 radius2

                -- Define handle length by the distance between
                -- both ends of the curve
                totalRadius = radius1 + radius2
                d2Base = Basics.min (v * handleLenRate) (V2.distance p1 p3 / totalRadius)
                -- Take into account when circles are overlapping
                d2 = d2Base * (Basics.min 1 (d * 2 / (radius1 + radius2)))

                -- Length of the handles
                handle1Length = radius1 * d2
                handle2Length = radius2 * d2

                -- Create the metaball
                theConnection =
                    { p1 = p1, p2 = p2, p3 = p3, p4 = p4
                    , h1 = vecAt p1 (angle1 - halfPi) handle1Length
                    , h2 = vecAt p2 (angle2 + halfPi) handle1Length
                    , h3 = vecAt p3 (angle3 + halfPi) handle2Length
                    , h4 = vecAt p4 (angle4 - halfPi) handle2Length
                    , escaped = d > radius1, radius = radius2
                    , builtFrom = ( circle1, circle2 )
                    }

                vecToSquarePath vec =
                    let locVec = V2.sub vec center1
                    in case ( V2.getX vec, V2.getY vec ) of
                        ( x, y ) ->
                            [ "M", String.fromFloat x, String.fromFloat y
                            , "L", String.fromFloat <| x + 5, String.fromFloat y
                            , "L", String.fromFloat <| x + 5, String.fromFloat <| y + 5
                            , "L", String.fromFloat x, String.fromFloat <| y + 5
                            , "L", String.fromFloat x, String.fromFloat y
                            ] |> String.join " "
            in
                ConnectionView
                    [ ( buildPath theConnection, Color "url(#gradient)" )
                    -- , ( vecToSquarePath theConnection.h1, Color "blue" )
                    -- , ( vecToSquarePath theConnection.h2, Color "blue" )
                    -- , ( vecToSquarePath theConnection.h3, Color "blue" )
                    -- , ( vecToSquarePath theConnection.h4, Color "blue" )
                    -- , ( vecToSquarePath theConnection.p1, Color "green" )
                    -- , ( vecToSquarePath theConnection.p2, Color "green" )
                    -- , ( vecToSquarePath theConnection.p3, Color "green" )
                    -- , ( vecToSquarePath theConnection.p4, Color "green" )
                    ]


group : Float -> Float -> List Circle -> Group
group t opacity circles =
    let
        animatedCircles = List.map (applyTweens t) circles
        indexedCircles =
            animatedCircles |> List.indexedMap Tuple.pair
        connections =
            List.foldr (\(i, circle1) allConnections ->
                allConnections ++
                    List.foldr (\(j, circle2) circleConnections ->
                        if (j < i) then
                            case connect circle1 circle2 of
                                NoConnection -> circleConnections
                                ConnectionView connection ->
                                    connection :: circleConnections
                        else circleConnections
                    ) [] indexedCircles
            ) [] indexedCircles
    in
        Group
            { circles = animatedCircles
            , connections = List.concat <| List.filter (not << List.isEmpty) connections
            , opacity = opacity
            }


scene : Float -> ( Float, Float )  -> ( Int, Int ) -> List (Float, List Circle) -> Scene
scene t ( w, h ) ( mouseX, mouseY ) startFrom =
    let
        circleAtCursor = Circle (vec2 (toFloat mouseX) (toFloat mouseY)) 100 [] (vec2 0 0)
        convertGroup ( opacity, circles ) =
            group t opacity circles
    in
        Scene <| List.map convertGroup startFrom


getLocT : Float -> Float -> Float -> Float
getLocT start end globt =
    let
        -- _ = Debug.log "globt" globt
        loct = (globt - (floor (globt / loop) |> toFloat) * loop) / loop
        clamped = clamp start end loct
    in
        clamped / (end - start)


applyTweens : Float -> Circle -> Circle
applyTweens t toCircle =
    let
        applyPos t_ tween ( curX, curY ) =
            case tween of
                Translate { from, to, start, end } ->
                    let tloc = getLocT start end t_
                    in
                        case ( ( V2.getX from, V2.getY from ), ( V2.getX to, V2.getY to ) ) of
                            ( ( fromX, fromY ), ( toX, toY ) ) ->
                                ( curX + fromX + ((toX - fromX) * tloc)
                                , curY + fromY + ((toY - fromY) * tloc)
                                )

        translateTo =
            List.foldl (applyPos t) (0, 0) toCircle.tweens
    in case translateTo of
        ( x, y ) ->
            { toCircle
            | transform = vec2 x y
            }


extractTransform : Transform -> String
extractTransform transform =
    case ( V2.getX transform, V2.getY transform ) of
        ( tx, ty ) ->
            "translate(" ++ String.fromFloat tx ++ "," ++ String.fromFloat ty ++ ")"



toCircles : Float -> (Float, Float) -> Model -> List (Float, List Circle)
toCircles t (w, h) model =
    let
        convertGroup groupIndex theGroup =
            ( theGroup.opacity
            , List.indexedMap
                (\circleIndex (pos, radius) ->
                    let
                        shiftX = w * sin (t / 2000) * (toFloat circleIndex / 10) * (toFloat groupIndex / 10)
                        shiftY = h * cos (t / 2000) * (toFloat circleIndex / 10) * (toFloat groupIndex / 10)
                    in
                        circle ( V2.getX pos - shiftX, V2.getY pos - shiftY) radius []
                    -- circle ( (w * sin (t / 2000) * 0.5),(h * cos (t / 2000)) ) radius []
                        -- [ Translate { from = vec2 0 0, to = vec2 (50 * circleIndex |> toFloat) 100, start = 0, end = 0.5 }
                        -- , Translate { from = vec2 0 0, to = vec2 -100 -100, start = 0.5, end = 1.0 }
                        -- ]
                )
                theGroup.circles
            )
    in
        List.indexedMap convertGroup model.groups


view : Viewport {} -> Float -> Float -> ( Int, Int ) -> Model -> Html a
view vp t dt mousePos model =
    let
        (Product.Palette colorOne colorTwo colorThree) = Product.getPalette product
        groupsCount = List.length model.groups
        ( w, h ) = ( V2.getX vp.size, V2.getY vp.size )
        (Scene groups) = scene t ( w, h ) mousePos <| toCircles t ( w, h ) model
        drawCircle groupIdx ({ origin, radius, transform }) =
                let
                    transformTo = V2.add origin transform
                in
                    S.circle
                        [ SA.cx <| String.fromFloat <| V2.getX transformTo
                        , SA.cy <| String.fromFloat <| V2.getY transformTo
                        , SA.r  <| String.fromFloat radius
                        -- , SA.transform <| extractTransform transform
                        -- , SA.fill <| "url(#gradient" ++ String.fromInt groupIdx ++ ")"
                        , SA.fill <| "url(#gradient" ++ String.fromInt groupIdx ++ ")"
                        ]
                        [ ]
        drawPath groupIdx ( pathStr, _ ) =
            S.path [ d pathStr, fill <| "url(#gradient" ++ String.fromInt groupIdx ++ ")" ] []
        drawGroup groupIdx (Group { circles, connections, opacity }) =
            S.g [ SA.style <| "opacity: " ++ String.fromFloat opacity ]
                (
                List.map (drawCircle groupIdx) circles ++
                List.map (drawPath groupIdx) connections
                )
        gradientStop offset color opacity =
            S.stop
                [ SA.offset <| String.fromFloat offset
                , SA.stopColor color
                --, SA.stopOpacity <| String.fromFloat opacity
                ]
                []
        gradient groupIdx gradientPos opacity =
            S.linearGradient
                [ SA.id <| "gradient" ++ String.fromInt groupIdx
                , SA.x1 (250 * groupIdx |> String.fromInt)
                , SA.y1 (250 * groupIdx |> String.fromInt)
                -- , SA.x2 (w |> String.fromFloat)
                -- , SA.y2 (h |> String.fromFloat)
                -- , SA.x1 (V2.getX gradientPos |> String.fromFloat)
                -- , SA.y1 (V2.getY gradientPos |> String.fromFloat)
                -- , SA.r (527.5685 * (toFloat (groupIdx + 1)) |> String.fromFloat)
                , SA.r "527.5685"
                , SA.gradientUnits "userSpaceOnUse"
                ]
                [ gradientStop 0.0 colorOne opacity
                , gradientStop 0.5 colorTwo opacity
                , gradientStop 1.0 colorThree opacity
                ]
        defs =
                List.indexedMap
                        (\groupIdx { opacity, gradientCenter } ->
                            gradient groupIdx gradientCenter opacity
                        )
                        model.groups
                    |> S.defs [ ]
    in
        S.svg
            [ SA.width <| String.fromFloat w, height <| String.fromFloat h ]
            (defs :: List.indexedMap drawGroup groups)
