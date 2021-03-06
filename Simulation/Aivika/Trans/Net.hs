
-- |
-- Module     : Simulation.Aivika.Trans.Net
-- Copyright  : Copyright (c) 2009-2017, David Sorokin <david.sorokin@gmail.com>
-- License    : BSD3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 8.0.1
--
-- The module defines a 'Net' arrow that can be applied to modeling the queue networks
-- like the 'Processor' arrow from another module. Only the former has a more efficient
-- implementation of the 'Arrow' interface than the latter, although at the cost of
-- some decreasing in generality.
--
-- While the @Processor@ type is just a function that transforms the input 'Stream' into another,
-- the @Net@ type is actually an automaton that has an implementation very similar to that one
-- which the 'Circuit' type has, only the computations occur in the 'Process' monad. But unlike
-- the @Circuit@ type, the @Net@ type doesn't allow declaring recursive definitions, being based on
-- continuations.
--
-- In a nutshell, the @Net@ type is an interchangeable alternative to the @Processor@ type
-- with its weaknesses and strengths. The @Net@ arrow is useful for constructing computations
-- with help of the proc-notation to be transformed then to the @Processor@ computations that
-- are more general in nature and more easy-to-use but which computations created with help of
-- the proc-notation are not so efficient.
--
module Simulation.Aivika.Trans.Net
       (-- * Net Arrow
        Net(..),
        iterateNet,
        iterateNetMaybe,
        iterateNetEither,
        -- * Net Primitives
        emptyNet,
        arrNet,
        accumNet,
        withinNet,
        -- * Specifying Identifier
        netUsingId,
        -- * Arrival Net
        arrivalNet,
        -- * Delaying Net
        delayNet,
        -- * Interchanging Nets with Processors
        netProcessor,
        processorNet,
        -- * Debugging
        traceNet) where

import qualified Control.Category as C
import Control.Arrow
import Control.Monad.Trans

import Simulation.Aivika.Trans.Ref.Base
import Simulation.Aivika.Trans.DES
import Simulation.Aivika.Trans.Parameter
import Simulation.Aivika.Trans.Simulation
import Simulation.Aivika.Trans.Dynamics
import Simulation.Aivika.Trans.Event
import Simulation.Aivika.Trans.Cont
import Simulation.Aivika.Trans.Process
import Simulation.Aivika.Trans.Stream
import Simulation.Aivika.Trans.QueueStrategy
import Simulation.Aivika.Trans.Resource.Base
import Simulation.Aivika.Trans.Processor
import Simulation.Aivika.Trans.Circuit
import Simulation.Aivika.Arrival (Arrival(..))

-- | Represents the net as an automaton working within the 'Process' computation.
newtype Net m a b =
  Net { runNet :: a -> Process m (b, Net m a b)
        -- ^ Run the net.
      }

instance MonadDES m => C.Category (Net m) where

  {-# INLINABLE id #-}
  id = Net $ \a -> return (a, C.id)

  {-# INLINABLE (.) #-}
  (.) = dot
    where 
      (Net g) `dot` (Net f) =
        Net $ \a ->
        do (b, p1) <- f a
           (c, p2) <- g b
           return (c, p2 `dot` p1)

instance MonadDES m => Arrow (Net m) where

  {-# INLINABLE arr #-}
  arr f = Net $ \a -> return (f a, arr f)

  {-# INLINABLE first #-}
  first (Net f) =
    Net $ \(b, d) ->
    do (c, p) <- f b
       return ((c, d), first p)

  {-# INLINABLE second #-}
  second (Net f) =
    Net $ \(d, b) ->
    do (c, p) <- f b
       return ((d, c), second p)

  {-# INLINABLE (***) #-}
  (Net f) *** (Net g) =
    Net $ \(b, b') ->
    do ((c, p1), (c', p2)) <- zipProcessParallel (f b) (g b')
       return ((c, c'), p1 *** p2)
       
  {-# INLINABLE (&&&) #-}
  (Net f) &&& (Net g) =
    Net $ \b ->
    do ((c, p1), (c', p2)) <- zipProcessParallel (f b) (g b)
       return ((c, c'), p1 &&& p2)

instance MonadDES m => ArrowChoice (Net m) where

  {-# INLINABLE left #-}
  left x@(Net f) =
    Net $ \ebd ->
    case ebd of
      Left b ->
        do (c, p) <- f b
           return (Left c, left p)
      Right d ->
        return (Right d, left x)

  {-# INLINABLE right #-}
  right x@(Net f) =
    Net $ \edb ->
    case edb of
      Right b ->
        do (c, p) <- f b
           return (Right c, right p)
      Left d ->
        return (Left d, right x)

  {-# INLINABLE (+++) #-}
  x@(Net f) +++ y@(Net g) =
    Net $ \ebb' ->
    case ebb' of
      Left b ->
        do (c, p1) <- f b
           return (Left c, p1 +++ y)
      Right b' ->
        do (c', p2) <- g b'
           return (Right c', x +++ p2)

  {-# INLINABLE (|||) #-}
  x@(Net f) ||| y@(Net g) =
    Net $ \ebc ->
    case ebc of
      Left b ->
        do (d, p1) <- f b
           return (d, p1 ||| y)
      Right b' ->
        do (d, p2) <- g b'
           return (d, x ||| p2)

-- | A net that never finishes its work.
emptyNet :: MonadDES m => Net m a b
{-# INLINABLE emptyNet #-}
emptyNet = Net $ const neverProcess

-- | Create a simple net by the specified handling function
-- that runs the discontinuous process for each input value to get an output.
arrNet :: MonadDES m => (a -> Process m b) -> Net m a b
{-# INLINABLE arrNet #-}
arrNet f =
  let x =
        Net $ \a ->
        do b <- f a
           return (b, x)
  in x

-- | Accumulator that outputs a value determined by the supplied function.
accumNet :: MonadDES m => (acc -> a -> Process m (acc, b)) -> acc -> Net m a b
{-# INLINABLE accumNet #-}
accumNet f acc =
  Net $ \a ->
  do (acc', b) <- f acc a
     return (b, accumNet f acc') 

-- | Involve the computation with side effect when processing the input.
withinNet :: MonadDES m => Process m () -> Net m a a
{-# INLINABLE withinNet #-}
withinNet m =
  Net $ \a ->
  do { m; return (a, withinNet m) }

-- | Create a net that will use the specified process identifier.
-- It can be useful to refer to the underlying 'Process' computation which
-- can be passivated, interrupted, canceled and so on. See also the
-- 'processUsingId' function for more details.
netUsingId :: MonadDES m => ProcessId m -> Net m a b -> Net m a b
{-# INLINABLE netUsingId #-}
netUsingId pid (Net f) =
  Net $ processUsingId pid . f

-- | Transform the net to an equivalent processor (a rather cheap transformation).
netProcessor :: MonadDES m => Net m a b -> Processor m a b
{-# INLINABLE netProcessor #-}
netProcessor = Processor . loop
  where loop x as =
          Cons $
          do (a, as') <- runStream as
             (b, x') <- runNet x a
             return (b, loop x' as')

-- | Transform the processor to a similar net (a more costly transformation).
processorNet :: MonadDES m => Processor m a b -> Net m a b
{-# INLINABLE processorNet #-}
processorNet x =
  Net $ \a ->
  do readingA <- liftSimulation $ newResourceWithMaxCount FCFS 0 (Just 1)
     writingA <- liftSimulation $ newResourceWithMaxCount FCFS 1 (Just 1)
     readingB <- liftSimulation $ newResourceWithMaxCount FCFS 0 (Just 1)
     writingB <- liftSimulation $ newResourceWithMaxCount FCFS 1 (Just 1)
     conting  <- liftSimulation $ newResourceWithMaxCount FCFS 0 (Just 1)
     refA <- liftSimulation $ newRef Nothing
     refB <- liftSimulation $ newRef Nothing
     let input =
           do requestResource readingA
              Just a <- liftEvent $ readRef refA
              liftEvent $ writeRef refA Nothing
              releaseResource writingA
              return (a, Cons input)
         consume bs =
           do (b, bs') <- runStream bs
              requestResource writingB
              liftEvent $ writeRef refB (Just b)
              releaseResource readingB
              requestResource conting
              consume bs'
         loop a =
           do requestResource writingA
              liftEvent $ writeRef refA (Just a)
              releaseResource readingA
              requestResource readingB
              Just b <- liftEvent $ readRef refB
              liftEvent $ writeRef refB Nothing
              releaseResource writingB
              return (b, Net $ \a -> releaseResource conting >> loop a)
     spawnProcess $
       consume $ runProcessor x (Cons input)
     loop a

-- | A net that adds the information about the time points at which 
-- the values were received.
arrivalNet :: MonadDES m => Net m a (Arrival a)
{-# INLINABLE arrivalNet #-}
arrivalNet =
  let loop t0 =
        Net $ \a ->
        do t <- liftDynamics time
           let b = Arrival { arrivalValue = a,
                             arrivalTime  = t,
                             arrivalDelay = 
                               case t0 of
                                 Nothing -> Nothing
                                 Just t0 -> Just (t - t0) }
           return (b, loop $ Just t)
  in loop Nothing

-- | Delay the input by one step using the specified initial value.
delayNet :: MonadDES m => a -> Net m a a
{-# INLINABLE delayNet #-}
delayNet a0 =
  Net $ \a ->
  return (a0, delayNet a)

-- | Iterate infinitely using the specified initial value.
iterateNet :: MonadDES m => Net m a a -> a -> Process m ()
{-# INLINABLE iterateNet #-}
iterateNet (Net f) a =
  do (a', x) <- f a
     iterateNet x a'

-- | Iterate the net using the specified initial value
-- until 'Nothing' is returned within the 'Net' computation.
iterateNetMaybe :: MonadDES m => Net m a (Maybe a) -> a -> Process m ()
{-# INLINABLE iterateNetMaybe #-}
iterateNetMaybe (Net f) a =
  do (a', x) <- f a
     case a' of
       Nothing -> return ()
       Just a' -> iterateNetMaybe x a'

-- | Iterate the net using the specified initial value
-- until the 'Left' result is returned within the 'Net' computation.
iterateNetEither :: MonadDES m => Net m a (Either b a) -> a -> Process m b
{-# INLINABLE iterateNetEither #-}
iterateNetEither (Net f) a =
  do (ba', x) <- f a
     case ba' of
       Left b'  -> return b'
       Right a' -> iterateNetEither x a'

-- | Show the debug messages with the current simulation time.
traceNet :: MonadDES m
            => Maybe String
            -- ^ the request message
            -> Maybe String
            -- ^ the response message
            -> Net m a b
            -- ^ a net
            -> Net m a b
{-# INLINABLE traceNet #-}
traceNet request response x = Net $ loop x where
  loop x a =
    do (b, x') <-
         case request of
           Nothing -> runNet x a
           Just message -> 
             traceProcess message $
             runNet x a
       case response of
         Nothing -> return (b, Net $ loop x')
         Just message ->
           traceProcess message $
           return (b, Net $ loop x') 
