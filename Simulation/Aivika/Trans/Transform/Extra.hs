
-- |
-- Module     : Simulation.Aivika.Trans.Transform.Extra
-- Copyright  : Copyright (c) 2009-2017, David Sorokin <david.sorokin@gmail.com>
-- License    : BSD3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 8.0.1
--
-- This module defines auxiliary computations such as interpolation ones
-- that complement the memoization, for example. There are scan computations too.
--

module Simulation.Aivika.Trans.Transform.Extra
       (-- * Interpolation
        initTransform,
        discreteTransform,
        interpolatingTransform,
        -- * Scans
        scanTransform,
        scan1Transform) where

import Control.Monad
import Control.Monad.Fix

import Simulation.Aivika.Trans.Dynamics
import Simulation.Aivika.Trans.Dynamics.Extra
import Simulation.Aivika.Trans.Transform
import Simulation.Aivika.Trans.Transform.Memo

-- | A transform that returns the initial value.
initTransform :: Monad m => Transform m a a
{-# INLINE initTransform #-}
initTransform = Transform $ return . initDynamics

-- | A transform that discretizes the computation in the integration time points.
discreteTransform :: Monad m => Transform m a a
{-# INLINE discreteTransform #-}
discreteTransform = Transform $ return . discreteDynamics

-- | A tranform that interpolates the computation based on the integration time points only.
-- Unlike the 'discreteTransform' computation it knows about the intermediate 
-- time points that are used in the Runge-Kutta method.
interpolatingTransform :: Monad m => Transform m a a
{-# INLINE interpolatingTransform #-}
interpolatingTransform = Transform $ return . interpolateDynamics 

-- | Like the standard 'scanl1' function but applied to values in 
-- the integration time points. The accumulator values are transformed
-- according to the second argument, which should be either  
-- 'memo0Transform' or its unboxed version.
scan1Transform :: MonadFix m => (a -> a -> a) -> Transform m a a -> Transform m a a
{-# INLINE scan1Transform #-}
scan1Transform f (Transform tr) = Transform $ scan1Dynamics f tr

-- | Like the standard 'scanl' function but applied to values in 
-- the integration time points. The accumulator values are transformed
-- according to the third argument, which should be either
-- 'memo0Transform' or its unboxed version.
scanTransform :: MonadFix m => (a -> b -> a) -> a -> Transform m a a -> Transform m b a
{-# INLINE scanTransform #-}
scanTransform f acc (Transform tr) = Transform $ scanDynamics f acc tr
