{-# LANGUAGE GADTs #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE RecordWildCards #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Diagrams.TwoD.Offset
-- Copyright   :  (c) 2012 diagrams-lib team (see LICENSE)
-- License     :  BSD-style (see LICENSE)
-- Maintainer  :  diagrams-discuss@googlegroups.com
--
-- Compute offsets to segments in two dimensions.
-- 
-----------------------------------------------------------------------------
module Diagrams.TwoD.Offset 
    ( offsetSegment

    , OffsetOpts(..)
    , offsetTrail
    , offsetTrail'
    , offsetPath
    , offsetPath'

    , ExpandOpts(..)
    , expandTrail
    , expandTrail'
    , expandPath
    , expandPath'

    ) where

import Control.Applicative

import Data.AffineSpace
import Data.Monoid
import Data.Monoid.Inf
import Data.VectorSpace

import Data.Default.Class

import Diagrams.Core

import Diagrams.Attributes
import Diagrams.Located
import Diagrams.Parametric
import Diagrams.Path
import Diagrams.Segment
import Diagrams.Trail
import Diagrams.TrailLike
import Diagrams.TwoD.Arc
import Diagrams.TwoD.Curvature
import Diagrams.TwoD.Transform
import Diagrams.TwoD.Types
import Diagrams.TwoD.Vector

unitPerp :: R2 -> R2
unitPerp = normalized . perp

perpAtParam :: Segment Closed R2 -> Double -> R2
perpAtParam   (Linear (OffsetClosed a))  t = -unitPerp a 
perpAtParam s@(Cubic _ _ _)              t = -unitPerp a
  where
    (Cubic a _ _) = snd $ splitAtParam s t

-- | Compute the offset of a segment.  Given a segment compute the offset
--   curve that is a fixed distance from the original curve.  For linear
--   segments nothing special happens, the same linear segment is returned
--   with a point that is offset by a perpendicular vector of the given offset
--   length.
--
--   Cubic segments require a search for a subdivision of cubic segments that
--   gives an approximation of the offset within the given epsilon tolerance.
--   We must do this because the offset of a cubic is not a cubic itself (the
--   degree of the curve increases).  Cubics do, however, approach constant
--   curvature as we subdivide.  In light of this we scale the handles of
--   the offset cubic segment in proportion to the radius of curvature difference
--   between the original subsegment and the offset which will have a radius
--   increased by the offset parameter.
--
--   In the following example the blue lines are the original segments and
--   the alternating green and red lines are the resulting offset trail segments.
--
--   <<diagrams/cubicOffsetExample.svg#diagram=cubicOffsetExample&width=600>>
--
--   Note that when the original curve has a cusp, the offset curve forms a
--   radius around the cusp, and when there is a loop in the original curve,
--   there can be two cusps in the offset curve.
--
offsetSegment :: Double     -- ^ Epsilon value that represents the maximum 
                            --   allowed deviation from the true offset.  In
                            --   the current implementation each result segment
                            --   should be bounded by arcs that are plus or
                            --   minus epsilon from the radius of curvature of
                            --   the offset.
              -> Double     -- ^ Offset from the original segment, positive is
                            --   on the right of the curve, negative is on the
                            --   left.
              -> Segment Closed R2  -- ^ Original segment
              -> Located (Trail R2) -- ^ Resulting located (at the offset) trail.
offsetSegment _       r s@(Linear (OffsetClosed a))    = trailFromSegments [s] `at` origin .+^ va
  where va = -r *^ unitPerp a

offsetSegment epsilon r s@(Cubic a b (OffsetClosed c)) = t `at` origin .+^ va
  where
    t = trailFromSegments (go (radiusOfCurvature s 0.5))
    -- Perpendiculars to handles.
    va = -r *^ unitPerp a
    vc = -r *^ unitPerp (c ^-^ b)
    -- Split segments.
    ss = (\(a,b) -> [a,b]) $ splitAtParam s 0.5
    subdivided = concatMap (trailSegments . unLoc . offsetSegment epsilon r) ss

    -- Offset with handles scaled based on curvature.
    offset factor = bezier3 (a^*factor) ((b ^-^ c)^*factor ^+^ c ^+^ vc ^-^ va) (c ^+^ vc ^-^ va)
 
    -- We observe a corner.  Subdivide right away.
    go (Finite 0) = subdivided
    -- We have some curvature
    go roc
      | close     = [o]
      | otherwise = subdivided
      where
        -- We want the multiplicative factor that takes us from the original
        -- segment's radius of curvature roc, to roc + r.
        --
        -- r + sr = x * sr
        --
        o = offset $ case roc of
              Infinity  -> 1          -- Do the right thing.
              Finite sr -> 1 + r / sr 

        close = and [epsilon > (magnitude (p o ^+^ va ^-^ p s ^-^ pp s))
                    | t <- [0.25, 0.5, 0.75]
                    , let p = (`atParam` t)
                    , let pp = (r *^) . (`perpAtParam` t)
                    ]


-- > import Diagrams.TwoD.Offset
-- > import Diagrams.Coordinates 
-- >
-- > showExample :: Segment Closed R2 -> Diagram SVG R2
-- > showExample s = pad 1.1 . centerXY $ d # lc blue # lw 0.1 <> d' # lw 0.1
-- >   where
-- >       d  = stroke . fromSegments $ [s]
-- >       d' = mconcat . zipWith lc colors . map stroke . explodeTrail
-- >          $ offsetSegment 0.1 (-1) s
-- >            
-- >       colors = cycle [green, red]
-- > 
-- > cubicOffsetExample :: Diagram SVG R2
-- > cubicOffsetExample = hcat . map showExample $
-- >         [ bezier3 (10 &  0) (  5  & 18) (10 & 20)
-- >         , bezier3 ( 0 & 20) ( 10  & 10) ( 5 & 10)
-- >         , bezier3 (10 & 20) (  0  & 10) (10 &  0)
-- >         , bezier3 (10 & 20) ((-5) & 10) (10 &  0)
-- >         ]

-- Similar to (=<<).  This is when we want to map a function across something
-- located, but the result of the mapping will be transformable so we can
-- collapse the Located into the result.  This assumes that Located has the
-- meaning of mearly taking something that cannot be translated and lifting
-- it into a space with translation.
bindLoc :: (Transformable b, V a ~ V b) => (a -> b) -> Located a -> b
bindLoc f = join' . mapLoc f
  where
    join' (viewLoc -> (p,a)) = translate (p .-. origin) a

-- Helpers to get the start point and end point of something Located with ends.
atStartL,atEndL :: (AdditiveGroup v, EndValues a, V v ~ v, Codomain a ~ Located v) 
                => a -> Point v
atStartL (viewLoc . atStart -> (p,a)) = p .+^ a
atEndL   (viewLoc . atEnd   -> (p,a)) = p .+^ a

-- While we build offsets and expansions we will use the [Located (Segment Closed R2)]
-- and [Located (Trail R2)] intermediate representations.
locatedTrailSegments :: (InnerSpace v, OrderedField (Scalar v))
                     => Located (Trail v) -> [Located (Segment Closed v)]
locatedTrailSegments t = zipWith at (trailSegments (unLoc t)) (trailVertices t)


data OffsetOpts = OffsetOpts
    { offsetJoin :: LineJoin
    , offsetEpsilon :: Double
    } deriving (Eq, Show) -- , Read)

instance Default OffsetOpts where
    def = OffsetOpts def stdTolerance

offsetTrail' :: OffsetOpts -> Double -> Located (Trail R2) -> Located (Trail R2)
offsetTrail' OffsetOpts{..} r t = joinSegments j r ends . offset r $ t
    where
      offset r = map (bindLoc (offsetSegment offsetEpsilon r)) . locatedTrailSegments
      ends = tail . trailVertices $ t
      j = fromLineJoin offsetJoin

offsetTrail :: Double -> Located (Trail R2) -> Located (Trail R2)
offsetTrail = offsetTrail' def

offsetPath' :: OffsetOpts -> Double -> Path R2 -> Path R2
offsetPath' opts r = mconcat 
                   . map (bindLoc (trailLike . offsetTrail' opts r) . (`at` origin)) 
                   . pathTrails 

offsetPath :: Double -> Path R2 -> Path R2
offsetPath = offsetPath' def

data ExpandOpts = ExpandOpts
    { expandJoin :: LineJoin
    , expandCap  :: LineCap
    , expandEpsilon :: Double
    } deriving (Eq, Show) -- , Read)

instance Default ExpandOpts where
    def = ExpandOpts def def stdTolerance

expandTrail' :: ExpandOpts -> Double -> Located (Trail R2) -> Located (Trail R2)
expandTrail' ExpandOpts{..} r t = caps cap r s e (f r) (f $ -r)
    where
      offset r = map (bindLoc (offsetSegment expandEpsilon r)) . locatedTrailSegments
      f r = joinSegments (fromLineJoin expandJoin) r ends . offset r $ t
      ends = tail . trailVertices $ t
      s = atStartL t
      e = atEndL t
      cap = fromLineCap expandCap

expandTrail :: Double -> Located (Trail R2) -> Located (Trail R2)
expandTrail = expandTrail' def

expandPath' :: ExpandOpts -> Double -> Path R2 -> Path R2
expandPath' opts r = mconcat 
                   . map (bindLoc (trailLike . expandTrail' opts r) . (`at` origin)) 
                   . pathTrails

expandPath :: Double -> Path R2 -> Path R2
expandPath = expandPath' def

-- | When we expand a line (the original line runs through the center of offset
--   lines at  r  and  -r) there is some choice in what the ends will look like.
--   If we are using a circle brush we should see a half circle at each end.
--   Similar caps could be made for square brushes or simply stopping exactly at
--   the end with a straight line (a perpendicular line brush).
--
--   caps  takes the radius and the start and end points of the original line and
--   the offset trails going out and coming back.  The result is a new list of
--   trails with the caps included.
caps :: (Double -> P2 -> P2 -> P2 -> Trail R2)
     -> Double -> P2 -> P2 -> Located (Trail R2) -> Located (Trail R2) -> Located (Trail R2)
caps cap r s e fs bs = mconcat
    [ cap r s (atStartL bs) (atStartL fs)
    , unLoc fs
    , cap r e (atEndL fs) (atEndL bs)
    , reverseDomain (unLoc bs)
    ] `at` atStartL bs

-- | Take a LineCap style and give a function for building the cap from 
fromLineCap :: LineCap -> Double -> P2 -> P2 -> P2 -> Trail R2
fromLineCap c = case c of
    LineCapButt   -> capCut
    LineCapRound  -> capArc
    LineCapSquare -> capSquare

-- | Builds a cap that directly connects the ends.
capCut :: Double -> P2 -> P2 -> P2 -> Trail R2
capCut r c a b = fromSegments [straight (b .-. a)]

-- | Builds a cap with a square centered on the end.
capSquare :: Double -> P2 -> P2 -> P2 -> Trail R2
capSquare r c a b = unLoc $ fromVertices [ a, a .+^ v, b .+^ v, b ]
  where
    v = perp (c .-. a)

-- | Builds an arc to fit with a given radius, center, start, and end points.
--   A Negative r means a counter-clockwise arc
capArc :: Double -> P2 -> P2 -> P2 -> Trail R2
capArc r c a b = trailLike . moveTo c $ fs
  where
    fs | r < 0     = scale (-r) $ arcVCW (a .-. c) (b .-. c)
       | otherwise = scale r    $ arcV   (a .-. c) (b .-. c)

-- Arc helpers
arcV u v = arc (direction u) (direction v :: CircleFrac)

arcVCW u v = arcCW (direction u) (direction v :: CircleFrac)


-- | Join together a list of located trails with the given join style.  The
--   style is given as a function to compute the join given the local information
--   of the original vertex, the previous trail, and the next trail.  The result
--   is a single located trail.  A join radius is also given to aid in arc joins.
--
--   Note: this is not a general purpose join and assumes that we are joining an
--   offset trail.  For instance, a fixed radius arc will not fit between arbitrary
--   trails without trimming or extending.
joinSegments :: (Double -> P2 -> Located (Trail R2) -> Located (Trail R2) -> Trail R2)
             -> Double -> [Point R2] -> [Located (Trail R2)] -> Located (Trail R2)
joinSegments _ _ _ [] = mempty `at` origin
joinSegments j r es ts@(t:_) = mapLoc (<> t') $ t
  where
    t' = mconcat [j r e a b <> unLoc b | (e,(a,b)) <- zip es . (zip <*> tail) $ ts]

-- | Take a join style and give the join function to be used by joinSegments.
fromLineJoin :: LineJoin -> Double -> P2 -> Located (Trail R2) -> Located (Trail R2) -> Trail R2
fromLineJoin j = case j of
    LineJoinMiter -> joinSegmentIntersect
    LineJoinRound -> joinSegmentArc
    LineJoinBevel -> joinSegmentClip

-- TODO: The joinSegmentCut option is not in our standard line joins.  I don't know
-- how useful it is graphically, I mostly had it as it was useful for debugging

-- | Join with segments going back to the original corner.
joinSegmentCut :: Double -> P2 -> Located (Trail R2) -> Located (Trail R2) -> Trail R2
joinSegmentCut r e a b = fromSegments
    [ straight (e .-. atEndL a)
    , straight (atStartL b .-. e)
    ]

-- | Join by directly connecting the end points.  On an inside corner this
--   creates negative space for even-odd fill.  Here is where we would want to
--   use an arc or something else in the future.
joinSegmentClip :: Double -> P2 -> Located (Trail R2) -> Located (Trail R2) -> Trail R2
joinSegmentClip _ _ a b = fromSegments [straight $ atStartL b .-. atEndL a]

-- | Join with a radius arc.  On an inside corner this will loop around the interior
--   of the offset trail.  With a winding fill this will not be visible.
joinSegmentArc :: Double -> P2 -> Located (Trail R2) -> Located (Trail R2) -> Trail R2
joinSegmentArc r e a b = capArc r e (atEndL a) (atStartL b)

-- TODO: joinSegmentIntersect
joinSegmentIntersect :: Double -> P2 -> Located (Trail R2) -> Located (Trail R2) -> Trail R2
joinSegmentIntersect = error "joinSegmentIntersect not implemented."
