{-# LANGUAGE TypeFamilies, FlexibleContexts, UndecidableInstances #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Diagrams.Combinators
-- Copyright   :  (c) Brent Yorgey 2010
-- License     :  BSD-style (see LICENSE)
-- Maintainer  :  byorgey@cis.upenn.edu
-- Stability   :  experimental
-- Portability :  portable
--
-- Higher-level tools for combining diagrams.
--
-----------------------------------------------------------------------------

module Diagrams.Combinators where

import Graphics.Rendering.Diagrams
import Graphics.Rendering.Diagrams.Transform (HasLinearMap)

import Diagrams.Segment (Segment(..), segmentBounds)

import Data.AdditiveGroup
import Data.VectorSpace

import Data.Monoid
import Data.Default

-- | Place two diagrams next to each other along the given vector.
--   XXX write more. note where origin ends up.
beside :: ( Backend b, v ~ BSpace b, s ~ Scalar v
          , HasLinearMap v, InnerSpace v
          , AdditiveGroup s, Fractional s, Ord s
          , Monoid a
          )
       => v -> AnnDiagram b a -> AnnDiagram b a -> AnnDiagram b a
beside v d1@(Diagram _ (Bounds b1) _ _)
         d2@(Diagram _ (Bounds b2) _ _)
  = rebase (P $ b1 v *^ v) d1 `atop`
    rebase (P $ b2 (negateV v) *^ negateV v) d2

-- | @strut v@ is a diagram which produces no output, but for the
--   purposes of alignment and bounding regions acts like a
--   1-dimensional segment oriented along the vector @v@.  Useful for
--   manually creating separation between two diagrams.
strut :: ( BSpace b ~ v, Scalar v ~ s
         , InnerSpace v, Floating s, Ord s, AdditiveGroup s
         , Monoid a
         )
      => v -> AnnDiagram b a
strut v = mempty { bounds = segmentBounds (Linear v) }

-- XXX comment me
data Alignment = AlignLeft | AlignRight | AlignCenter

-- XXX comment me
data Positioning = PositionFront | PositionCenter | PositionBack

-- XXX comment me
data CatMethod v = CatSep (Scalar v)
                 | CatRep (Scalar v) Positioning
                 | CatDistrib (Scalar v) Positioning

-- XXX comment me
data CatOpts v = CatOpts
  { catDir      :: v
  , catMethod   :: CatMethod v
  , catAlignDir :: v
  , catAlign    :: Alignment
  }

instance (AdditiveGroup v, AdditiveGroup (Scalar v)) => Default (CatOpts v) where
  def = CatOpts { catDir      = zeroV
                , catMethod   = CatSep (zeroV)
                , catAlignDir = zeroV
                , catAlign    = AlignCenter
                }

-- XXX comment me
cat' :: (Backend b, BSpace b ~ v)
    => CatOpts v -> [AnnDiagram b a] -> AnnDiagram b a
cat' (CatOpts { catDir      = dir
              , catMethod   = meth
              , catAlignDir = aDir
              , catAlign    = algn
              })
     dias
  = undefined

-- cat

-- along

-- at

-- grid