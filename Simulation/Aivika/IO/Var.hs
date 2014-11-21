
{-# LANGUAGE TypeFamilies, FlexibleInstances, UndecidableInstances #-}

-- |
-- Module     : Simulation.Aivika.IO.Var
-- Copyright  : Copyright (c) 2009-2014, David Sorokin <david.sorokin@gmail.com>
-- License    : GPL-3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 7.8.3
--
-- This module defines a variable that is bound up with the event queue and 
-- that keeps the history of changes storing the values in arrays, which
-- allows using the variable in differential and difference equations of
-- System Dynamics within hybrid discrete-continuous simulation.
--
module Simulation.Aivika.IO.Var where

import Control.Monad.Trans

import Data.Array

import Simulation.Aivika.Trans.DES
import Simulation.Aivika.Trans.Internal.Specs
import Simulation.Aivika.Trans.Internal.Simulation
import Simulation.Aivika.Trans.Internal.Dynamics
import Simulation.Aivika.Trans.Internal.Event
import Simulation.Aivika.Trans.Ref
import Simulation.Aivika.Trans.Signal
import Simulation.Aivika.Trans.Template
import Simulation.Aivika.Trans.Var

import qualified Simulation.Aivika.Vector as V
import qualified Simulation.Aivika.Vector.Unboxed as UV

-- | The 'MonadIO' based monad is an instance of 'MonadVar'.
instance (MonadDES m, MonadIO m, MonadTemplate m) => MonadVar m where

  -- | A template-based implementation of the variable.
  data Var m a = 
    Var { varXS    :: UV.Vector Double,
          varMS    :: V.Vector a,
          varYS    :: V.Vector a,
          varChangedSource :: SignalSource m a }
     
  newVar a =
    Simulation $ \r ->
    do xs <- liftIO UV.newVector
       ms <- liftIO V.newVector
       ys <- liftIO V.newVector
       liftIO $ UV.appendVector xs $ spcStartTime $ runSpecs r
       liftIO $ V.appendVector ms a
       liftIO $ V.appendVector ys a
       s  <- invokeSimulation r newSignalSource
       return Var { varXS = xs,
                    varMS = ms,
                    varYS = ms,
                    varChangedSource = s }

  varMemo v =
    runEventWith CurrentEventsOrFromPast $
    Event $ \p ->
    liftIO $
    do let xs = varXS v
           ms = varMS v
           ys = varYS v
           t  = pointTime p
       count <- UV.vectorCount xs
       let i = count - 1
       x <- UV.readVector xs i
       if x < t
         then do a <- V.readVector ys i
                 UV.appendVector xs t
                 V.appendVector ms a
                 V.appendVector ys a
                 return a
         else if x == t
              then V.readVector ms i
              else do i <- UV.vectorBinarySearch xs t
                      if i >= 0
                        then V.readVector ms i
                        else V.readVector ms $ - (i + 1) - 1

  readVar v = 
    Event $ \p ->
    liftIO $
    do let xs = varXS v
           ys = varYS v
           t  = pointTime p
       count <- UV.vectorCount xs
       let i = count - 1
       x <- UV.readVector xs i
       if x <= t 
         then V.readVector ys i
         else do i <- UV.vectorBinarySearch xs t
                 if i >= 0
                   then V.readVector ys i
                   else V.readVector ys $ - (i + 1) - 1

  writeVar v a =
    Event $ \p ->
    do let xs = varXS v
           ms = varMS v
           ys = varYS v
           t  = pointTime p
           s  = varChangedSource v
       count <- liftIO $ UV.vectorCount xs
       let i = count - 1
       x <- liftIO $ UV.readVector xs i
       if t < x 
         then error "Cannot update the past data: writeVar."
         else if t == x
              then liftIO $ V.writeVector ys i $! a
              else liftIO $
                   do UV.appendVector xs t
                      V.appendVector ms $! a
                      V.appendVector ys $! a
       invokeEvent p $ triggerSignal s a

  modifyVar v f =
    Event $ \p ->
    do let xs = varXS v
           ms = varMS v
           ys = varYS v
           t  = pointTime p
           s  = varChangedSource v
       count <- liftIO $ UV.vectorCount xs
       let i = count - 1
       x <- liftIO $ UV.readVector xs i
       if t < x
         then error "Cannot update the past data: modifyVar."
         else if t == x
              then do a <- liftIO $ V.readVector ys i
                      let b = f a
                      liftIO $ V.writeVector ys i $! b
                      invokeEvent p $ triggerSignal s b
              else do a <- liftIO $ V.readVector ys i
                      let b = f a
                      liftIO $ UV.appendVector xs t
                      liftIO $ V.appendVector ms $! b
                      liftIO $ V.appendVector ys $! b
                      invokeEvent p $ triggerSignal s b

  freezeVar v =
    Event $ \p ->
    liftIO $
    do xs <- UV.freezeVector (varXS v)
       ms <- V.freezeVector (varMS v)
       ys <- V.freezeVector (varYS v)
       return (xs, ms, ys)
     
  varChanged v = publishSignal (varChangedSource v)

  varChanged_ v = mapSignal (const ()) $ varChanged v     