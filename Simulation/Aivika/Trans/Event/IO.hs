
{-# LANGUAGE TypeFamilies, FlexibleInstances, UndecidableInstances #-}

-- |
-- Module     : Simulation.Aivika.Trans.Event.IO
-- Copyright  : Copyright (c) 2009-2014, David Sorokin <david.sorokin@gmail.com>
-- License    : GPL-3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 7.8.3
--
-- The module defines a template-based event queue.
--
module Simulation.Aivika.Trans.Event.IO (EventQueueing) where

import Control.Monad
import Control.Monad.Trans

import Data.IORef

import qualified Simulation.Aivika.PriorityQueue as PQ

import Simulation.Aivika.Trans.Ref.Base
import Simulation.Aivika.Trans.DES
import Simulation.Aivika.Trans.Comp
import Simulation.Aivika.Trans.Template
import Simulation.Aivika.Trans.Internal.Types

-- | A template-based implementation of the 'EventQueueing' type class.
instance TemplateIO m => EventQueueing m where

  data EventQueue m =
    EventQueue { queuePQ :: PQ.PriorityQueue (Point m -> m ()),
                 -- ^ the underlying priority queue
                 queueBusy :: IORef Bool,
                 -- ^ whether the queue is currently processing events
                 queueTime :: IORef Double
                 -- ^ the actual time of the event queue
               }
  
  newEventQueue specs =
    liftIO $
    do f <- newIORef False
       t <- newIORef $ spcStartTime specs
       pq <- PQ.newQueue
       return EventQueue { queuePQ   = pq,
                           queueBusy = f,
                           queueTime = t }

  enqueueEvent t (Event m) =
    Event $ \p ->
    let pq = queuePQ $ runEventQueue $ pointRun p
    in liftIO $ PQ.enqueue pq t m

  runEventWith processing (Event e) =
    Dynamics $ \p ->
    do invokeDynamics p $ processEvents processing
       e p

  eventQueueCount =
    Event $
    liftIO . PQ.queueCount . queuePQ . runEventQueue . pointRun

-- | Process the pending events.
processPendingEventsCore :: TemplateIO m => Bool -> Dynamics m ()
processPendingEventsCore includingCurrentEvents = Dynamics r where
  r p =
    do let q = runEventQueue $ pointRun p
           f = queueBusy q
       f' <- liftIO $ readIORef f
       unless f' $
         do liftIO $ writeIORef f True
            call q p
            liftIO $ writeIORef f False
  call q p =
    do let pq = queuePQ q
           r  = pointRun p
       f <- liftIO $ PQ.queueNull pq
       unless f $
         do (t2, c2) <- liftIO $ PQ.queueFront pq
            let t = queueTime q
            t' <- liftIO $ readIORef t
            when (t2 < t') $ 
              error "The time value is too small: processPendingEventsCore"
            when ((t2 < pointTime p) ||
                  (includingCurrentEvents && (t2 == pointTime p))) $
              do liftIO $ writeIORef t t2
                 liftIO $ PQ.dequeue pq
                 let sc = pointSpecs p
                     t0 = spcStartTime sc
                     dt = spcDT sc
                     n2 = fromIntegral $ floor ((t2 - t0) / dt)
                 c2 $ p { pointTime = t2,
                          pointIteration = n2,
                          pointPhase = -1 }
                 call q p

-- | Process the pending events synchronously, i.e. without past.
processPendingEvents :: TemplateIO m => Bool -> Dynamics m ()
processPendingEvents includingCurrentEvents = Dynamics r where
  r p =
    do let q = runEventQueue $ pointRun p
           t = queueTime q
       t' <- liftIO $ readIORef t
       if pointTime p < t'
         then error $
              "The current time is less than " ++
              "the time in the queue: processPendingEvents"
         else invokeDynamics p m
  m = processPendingEventsCore includingCurrentEvents

-- | A memoized value.
processEventsIncludingCurrent :: TemplateIO m => Dynamics m ()
processEventsIncludingCurrent = processPendingEvents True

-- | A memoized value.
processEventsIncludingEarlier :: TemplateIO m => Dynamics m ()
processEventsIncludingEarlier = processPendingEvents False

-- | A memoized value.
processEventsIncludingCurrentCore :: TemplateIO m => Dynamics m ()
processEventsIncludingCurrentCore = processPendingEventsCore True

-- | A memoized value.
processEventsIncludingEarlierCore :: TemplateIO m => Dynamics m ()
processEventsIncludingEarlierCore = processPendingEventsCore True

-- | Process the events.
processEvents :: TemplateIO m => EventProcessing -> Dynamics m ()
processEvents CurrentEvents = processEventsIncludingCurrent
processEvents EarlierEvents = processEventsIncludingEarlier
processEvents CurrentEventsOrFromPast = processEventsIncludingCurrentCore
processEvents EarlierEventsOrFromPast = processEventsIncludingEarlierCore
