module Main where

import Control.Monad.Eff
import Data.Tuple(Tuple(..))
import DOM
import Signal
import Signal.Time
import Signal.DOM


type GameObject =
  { id :: String, css :: String
  , x :: Number, y :: Number
  , baseX :: Number, baseY :: Number
  , vx :: Number, vy :: Number
  }

type Bounds = { x1 :: Number, x2 :: Number, y1 :: Number, y2 :: Number }
bounds :: GameObject -> Bounds
bounds a = { x1: a.x + a.baseX, y1: a.y + a.baseY
           , x2: a.x + a.baseX + 64, y2: a.y + a.baseY + 64 }
intersects :: GameObject -> GameObject -> Boolean
intersects a b = not ((b'.x1 > a'.x2) || (b'.x2 < a'.x1)
                   || (b'.y1 > a'.y2) || (b'.y2 < a'.y1))
  where a' = bounds a
        b' = bounds b

foreign import renderObject """
  function renderObject(o) {
    return function() {
      var el = document.getElementById(o.id);
      el.setAttribute('class', o.css);
      el.setAttribute('style', 'left: '
        + (o.baseX + (o.x | 0)) + 'px; top: '
        + (o.baseY + (o.y | 0)) + 'px');
    }
  }""" :: forall e. GameObject -> Eff (dom :: DOM | e) Unit

initialPinkie :: GameObject
initialPinkie =
  { id: "pinkie", css: ""
  , x: 0, y: 0
  , baseX: 0, baseY: 276
  , vx: 0, vy: 0
   }

initialCoin :: GameObject
initialCoin =
  { id: "coin", css: ""
  , x: 1600, y: 40
  , baseX: 0, baseY: 0
  , vx: -6, vy: 0
 }

initialHater :: GameObject
initialHater =
  { id: "hater", css: ""
  , x: 1600, y: 300
  , baseX: 0, baseY: 0
  , vx: -8, vy: 0
 }

frameRate :: Signal Number
frameRate = every 33

ground :: Signal GameObject
ground = frameRate ~> \n ->
  { id: "ground", css: ""
  , x: ((n / 33) % 64) * -8, y: 0
  , baseX: -128, baseY: 384
  , vx: 0, vy: 0
  -- psc isn't able to infer the type of the Nothing here, unlike above
  }

reset :: GameObject -> GameObject -> GameObject
reset i o | (o.x + o.baseX) < -100
         || (o.y + o.baseY) < -100
         || (o.y + o.baseY) > 3000 = i
reset _ o = o

gravity :: GameObject -> GameObject
gravity o = o { vy = o.vy + 0.98 }

velocity :: GameObject -> GameObject
velocity o = o { x = o.x + o.vx
                       , y = o.y + o.vy }

solidGround :: GameObject -> GameObject
solidGround o =
  if o.y >= 0
  then o { y = 0, vy = 0, css = "" }
  else o

jump :: Boolean -> GameObject -> GameObject
jump true p@{ y = 0 } = p { vy = -20, css = "jumping"}
jump _ p = p

hated :: GameObject -> GameObject -> (GameObject -> GameObject) -> GameObject
hated _ p@{ css = "gameover" } _ =
  reset initialPinkie $ velocity $ p { vy = p.vy + 0.5 }
hated hater p _ | intersects hater p =
  velocity $ p { css = "gameover", vy = -15 }
hated _ p cont = cont p

pinkieLogic :: (Tuple Boolean GameObject) -> GameObject -> GameObject
pinkieLogic (Tuple jumpPressed hater) p =
  hated hater p
  (solidGround
   <<< gravity
   <<< velocity
   <<< jump jumpPressed
   )

pinkie :: Signal (Tuple Boolean GameObject) -> Signal GameObject
pinkie input = foldp pinkieLogic initialPinkie
               (sampleOn frameRate input)

haterLogic :: Time -> GameObject -> GameObject
haterLogic _ h =
  velocity $ reset initialHater h

hater :: Signal GameObject
hater = foldp haterLogic initialHater frameRate

coinLogic :: GameObject -> GameObject -> GameObject
coinLogic _ c |$ velocity $ reset initialCoin c { vy = c.vy * 2}
coinLogic pinkie c | intersects pinkie c =
  c { vx = 0, vy = -1}
coinLogic pinkie $ velocity $ reset initialCoin c

coin :: Signal GameObject -> Signal GameObject
coin = foldp coinLogic initialCoin

main :: Eff (dom :: DOM) Unit
main = do
  spaceBar <- keyPressed 32
  taps <- tap
  let pinkie' = pinkie $ zip (spaceBar <> taps) hater
      scene = ground <> hater <> pinkie' <> coin pinkie'
  runSignal $ scene ~> renderObject
