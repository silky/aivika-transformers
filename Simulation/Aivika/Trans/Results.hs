
{-# LANGUAGE FlexibleContexts, FlexibleInstances, UndecidableInstances, ExistentialQuantification, MultiParamTypeClasses, FunctionalDependencies, OverlappingInstances #-}

-- |
-- Module     : Simulation.Aivika.Trans.Results
-- Copyright  : Copyright (c) 2009-2017, David Sorokin <david.sorokin@gmail.com>
-- License    : BSD3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 8.0.1
--
-- The module allows exporting the simulation results from the model.
--
module Simulation.Aivika.Trans.Results
       (-- * Definitions Focused on Modeling
        Results,
        ResultTransform,
        ResultName,
        ResultProvider(..),
        results,
        expandResults,
        resultSummary,
        resultByName,
        resultByProperty,
        resultById,
        resultByIndex,
        resultBySubscript,
        ResultComputing(..),
        ResultListWithSubscript(..),
        ResultArrayWithSubscript(..),
        ResultVectorWithSubscript(..),
        -- * Definitions Focused on Using the Library
        ResultValue(..),
        resultsToIntValues,
        resultsToIntListValues,
        resultsToIntStatsValues,
        resultsToIntStatsEitherValues,
        resultsToIntTimingStatsValues,
        resultsToDoubleValues,
        resultsToDoubleListValues,
        resultsToDoubleStatsValues,
        resultsToDoubleStatsEitherValues,
        resultsToDoubleTimingStatsValues,
        resultsToStringValues,
        ResultPredefinedSignals(..),
        newResultPredefinedSignals,
        resultSignal,
        pureResultSignal,
        -- * Definitions Focused on Extending the Library 
        ResultSourceMap,
        ResultSource(..),
        ResultItem(..),
        ResultItemable(..),
        resultItemAsIntStatsEitherValue,
        resultItemAsDoubleStatsEitherValue,
        resultItemToIntValue,
        resultItemToIntListValue,
        resultItemToIntStatsValue,
        resultItemToIntStatsEitherValue,
        resultItemToIntTimingStatsValue,
        resultItemToDoubleValue,
        resultItemToDoubleListValue,
        resultItemToDoubleStatsValue,
        resultItemToDoubleStatsEitherValue,
        resultItemToDoubleTimingStatsValue,
        resultItemToStringValue,
        ResultObject(..),
        ResultProperty(..),
        ResultVector(..),
        memoResultVectorSignal,
        memoResultVectorSummary,
        ResultSeparator(..),
        ResultContainer(..),
        resultContainerPropertySource,
        resultContainerConstProperty,
        resultContainerIntegProperty,
        resultContainerProperty,
        resultContainerMapProperty,
        resultValueToContainer,
        resultContainerToValue,
        ResultData,
        ResultSignal(..),
        maybeResultSignal,
        textResultSource,
        timeResultSource,
        resultSourceToIntValues,
        resultSourceToIntListValues,
        resultSourceToIntStatsValues,
        resultSourceToIntStatsEitherValues,
        resultSourceToIntTimingStatsValues,
        resultSourceToDoubleValues,
        resultSourceToDoubleListValues,
        resultSourceToDoubleStatsValues,
        resultSourceToDoubleStatsEitherValues,
        resultSourceToDoubleTimingStatsValues,
        resultSourceToStringValues,
        resultSourceMap,
        resultSourceList,
        composeResults,
        computeResultValue) where

import Control.Monad
import Control.Monad.Trans

import qualified Data.Map as M
import qualified Data.Array as A
import qualified Data.Vector as V

import Data.Ix
import Data.Maybe
import Data.Monoid

import Simulation.Aivika.Trans.Parameter
import Simulation.Aivika.Trans.Simulation
import Simulation.Aivika.Trans.Dynamics
import Simulation.Aivika.Trans.Event
import Simulation.Aivika.Trans.Signal
import Simulation.Aivika.Trans.Statistics
import Simulation.Aivika.Trans.Statistics.Accumulator
import Simulation.Aivika.Trans.Ref
import qualified Simulation.Aivika.Trans.Ref.Base as B
import Simulation.Aivika.Trans.Var
import Simulation.Aivika.Trans.QueueStrategy
import qualified Simulation.Aivika.Trans.Queue as Q
import qualified Simulation.Aivika.Trans.Queue.Infinite as IQ
import Simulation.Aivika.Trans.Arrival
import Simulation.Aivika.Trans.Server
import Simulation.Aivika.Trans.Activity
import Simulation.Aivika.Trans.Operation
import Simulation.Aivika.Trans.Results.Locale.Types
import Simulation.Aivika.Trans.SD
import Simulation.Aivika.Trans.DES
import Simulation.Aivika.Trans.Resource
import qualified Simulation.Aivika.Trans.Resource.Preemption as PR

-- | Represents a provider of the simulation results. It is usually something, or
-- an array of something, or a list of such values which can be simulated to get data.
class MonadDES m => ResultProvider p m | p -> m where
  
  -- | Return the source of simulation results by the specified name, description and provider. 
  resultSource :: ResultName -> ResultDescription -> p -> ResultSource m
  resultSource name descr = resultSource' name [name] i [i]
    where i = (UserDefinedResultId $ UserDefinedResult name descr title)
          title = resultNameToTitle name
  
  -- | Return the source of simulation results by the specified name, description, title and provider. 
  resultSource3 :: ResultName -> ResultDescription -> ResultDescription -> p -> ResultSource m
  resultSource3 name descr title = resultSource' name [name] i [i]
    where i = (UserDefinedResultId $ UserDefinedResult name descr title)

  -- | Return the source of simulation results by the specified name, its name path,
  -- identifier, the corresponding indentifier path and provider. 
  resultSource' :: ResultName -> [ResultName] -> ResultId -> [ResultId] -> p -> ResultSource m

-- | It associates the result sources with their names.
type ResultSourceMap m = M.Map ResultName (ResultSource m)

-- | Encapsulates the result source.
data ResultSource m = ResultItemSource (ResultItem m)
                      -- ^ The source consisting of a single item.
                    | ResultObjectSource (ResultObject m)
                      -- ^ An object-like source.
                    | ResultVectorSource (ResultVector m)
                      -- ^ A vector-like structure.
                    | ResultSeparatorSource ResultSeparator
                      -- ^ This is a separator text.

-- | The simulation results represented by a single item.
data ResultItem m = forall a. ResultItemable a => ResultItem (a m)

-- | Represents a type class for actual representing the items.
class ResultItemable a where

  -- | The item name.
  resultItemName :: a m -> ResultName
  
  -- | The item name path.
  resultItemNamePath :: a m -> [ResultName]
  
  -- | The item identifier.
  resultItemId :: a m -> ResultId
  
  -- | The item identifier path.
  resultItemIdPath :: a m -> [ResultId]

  -- | Whether the item emits a signal.
  resultItemSignal :: MonadDES m => a m -> ResultSignal m

  -- | Return an expanded version of the item, for example,
  -- when the statistics item is exanded to an object
  -- having the corresponded properties for count, average,
  -- deviation, minimum, maximum and so on.
  resultItemExpansion :: MonadDES m => a m -> ResultSource m
  
  -- | Return usually a short version of the item, i.e. its summary,
  -- but values of some data types such as statistics can be
  -- implicitly expanded to an object with the corresponded
  -- properties.
  resultItemSummary :: MonadDES m => a m -> ResultSource m
  
  -- | Try to return integer numbers in time points.
  resultItemAsIntValue :: MonadDES m => a m -> Maybe (ResultValue Int m)

  -- | Try to return lists of integer numbers in time points. 
  resultItemAsIntListValue :: MonadDES m => a m -> Maybe (ResultValue [Int] m)

  -- | Try to return statistics based on integer numbers.
  resultItemAsIntStatsValue :: MonadDES m => a m -> Maybe (ResultValue (SamplingStats Int) m)

  -- | Try to return timing statistics based on integer numbers.
  resultItemAsIntTimingStatsValue :: MonadDES m => a m -> Maybe (ResultValue (TimingStats Int) m)

  -- | Try to return double numbers in time points.
  resultItemAsDoubleValue :: MonadDES m => a m -> Maybe (ResultValue Double m)
  
  -- | Try to return lists of double numbers in time points. 
  resultItemAsDoubleListValue :: MonadDES m => a m -> Maybe (ResultValue [Double] m)

  -- | Try to return statistics based on double numbers.
  resultItemAsDoubleStatsValue :: MonadDES m => a m -> Maybe (ResultValue (SamplingStats Double) m)

  -- | Try to return timing statistics based on integer numbers.
  resultItemAsDoubleTimingStatsValue :: MonadDES m => a m -> Maybe (ResultValue (TimingStats Double) m)

  -- | Try to return string representations in time points.
  resultItemAsStringValue :: MonadDES m => a m -> Maybe (ResultValue String m)

-- | Try to return a version optimised for fast aggregation of the statistics based on integer numbers.
resultItemAsIntStatsEitherValue :: (MonadDES m, ResultItemable a) => a m -> Maybe (ResultValue (Either Int (SamplingStats Int)) m)
resultItemAsIntStatsEitherValue x =
  case x1 of
    Just a1 -> Just $ mapResultValue Left a1
    Nothing ->
      case x2 of
        Just a2 -> Just $ mapResultValue Right a2
        Nothing -> Nothing
  where
    x1 = resultItemAsIntValue x
    x2 = resultItemAsIntStatsValue x

-- | Try to return a version optimised for fast aggregation of the statistics based on double floating point numbers.
resultItemAsDoubleStatsEitherValue :: (MonadDES m, ResultItemable a) => a m -> Maybe (ResultValue (Either Double (SamplingStats Double)) m)
resultItemAsDoubleStatsEitherValue x =
  case x1 of
    Just a1 -> Just $ mapResultValue Left a1
    Nothing ->
      case x2 of
        Just a2 -> Just $ mapResultValue Right a2
        Nothing -> Nothing
  where
    x1 = resultItemAsDoubleValue x
    x2 = resultItemAsDoubleStatsValue x

-- | Return integer numbers in time points.
resultItemToIntValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue Int m
resultItemToIntValue x =
  case resultItemAsIntValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as a source of integer numbers: resultItemToIntValue"

-- | Return lists of integer numbers in time points. 
resultItemToIntListValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue [Int] m
resultItemToIntListValue x =
  case resultItemAsIntListValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as a source of lists of integer numbers: resultItemToIntListValue"

-- | Return statistics based on integer numbers.
resultItemToIntStatsValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue (SamplingStats Int) m
resultItemToIntStatsValue x =
  case resultItemAsIntStatsValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as a source of statistics based on integer numbers: resultItemToIntStatsValue"

-- | Return a version optimised for fast aggregation of the statistics based on integer numbers.
resultItemToIntStatsEitherValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue (Either Int (SamplingStats Int)) m
resultItemToIntStatsEitherValue x =
  case resultItemAsIntStatsEitherValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as an optimised source of statistics based on integer numbers: resultItemToIntStatsEitherValue"

-- | Return timing statistics based on integer numbers.
resultItemToIntTimingStatsValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue (TimingStats Int) m
resultItemToIntTimingStatsValue x =
  case resultItemAsIntTimingStatsValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as a source of timing statistics based on integer numbers: resultItemToIntTimingStatsValue"

-- | Return double numbers in time points.
resultItemToDoubleValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue Double m
resultItemToDoubleValue x =
  case resultItemAsDoubleValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as a source of double-precision floating-point numbers: resultItemToDoubleValue"
  
-- | Return lists of double numbers in time points. 
resultItemToDoubleListValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue [Double] m
resultItemToDoubleListValue x =
  case resultItemAsDoubleListValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as a source of lists of double-precision floating-point numbers: resultItemToDoubleListValue"

-- | Return statistics based on double numbers.
resultItemToDoubleStatsValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue (SamplingStats Double) m
resultItemToDoubleStatsValue x =
  case resultItemAsDoubleStatsValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as a source of statistics based on double-precision floating-point numbers: resultItemToDoubleStatsValue"

-- | Return a version optimised for fast aggregation of the statistics based on double floating point numbers.
resultItemToDoubleStatsEitherValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue (Either Double (SamplingStats Double)) m
resultItemToDoubleStatsEitherValue x =
  case resultItemAsDoubleStatsEitherValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as an optimised source of statistics based on double-precision floating-point numbers: resultItemToDoubleStatsEitherValue"

-- | Return timing statistics based on integer numbers.
resultItemToDoubleTimingStatsValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue (TimingStats Double) m
resultItemToDoubleTimingStatsValue x =
  case resultItemAsDoubleTimingStatsValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as a source of timing statistics based on double-precision floating-point numbers: resultItemToDoubleTimingStatsValue"

-- | Return string representations in time points.
resultItemToStringValue :: (MonadDES m, ResultItemable a) => a m -> ResultValue String m
resultItemToStringValue x =
  case resultItemAsStringValue x of
    Just a -> a
    Nothing ->
      error $
      "Cannot represent " ++ resultItemName x ++
      " as a source of strings: resultItemToStringValue"

-- | The simulation results represented by an object having properties.
data ResultObject m =
  ResultObject { resultObjectName :: ResultName,
                 -- ^ The object name.
                 resultObjectId :: ResultId,
                 -- ^ The object identifier.
                 resultObjectTypeId :: ResultId,
                 -- ^ The object type identifier.
                 resultObjectProperties :: [ResultProperty m],
                 -- ^ The object properties.
                 resultObjectSignal :: ResultSignal m,
                 -- ^ A combined signal if present.
                 resultObjectSummary :: ResultSource m
                 -- ^ A short version of the object, i.e. its summary.
               }

-- | The object property containing the simulation results.
data ResultProperty m =
  ResultProperty { resultPropertyLabel :: ResultName,
                   -- ^ The property short label.
                   resultPropertyId :: ResultId,
                   -- ^ The property identifier.
                   resultPropertySource :: ResultSource m
                   -- ^ The simulation results supplied by the property.
                 }

-- | The simulation results represented by a vector.
data ResultVector m =
  ResultVector { resultVectorName :: ResultName,
                 -- ^ The vector name.
                 resultVectorId :: ResultId,
                 -- ^ The vector identifier.
                 resultVectorItems :: A.Array Int (ResultSource m),
                 -- ^ The results supplied by the vector items.
                 resultVectorSubscript :: A.Array Int ResultName,
                 -- ^ The subscript used as a suffix to create item names.
                 resultVectorSignal :: ResultSignal m,
                 -- ^ A combined signal if present.
                 resultVectorSummary :: ResultSource m
                 -- ^ A short version of the vector, i.e. summary.
               }

-- | Calculate the result vector signal and memoize it in a new vector.
memoResultVectorSignal :: MonadDES m => ResultVector m -> ResultVector m
memoResultVectorSignal x =
  x { resultVectorSignal =
         foldr (<>) mempty $ map resultSourceSignal $ A.elems $ resultVectorItems x }

-- | Calculate the result vector summary and memoize it in a new vector.
memoResultVectorSummary :: MonadDES m => ResultVector m -> ResultVector m
memoResultVectorSummary x =
  x { resultVectorSummary =
         ResultVectorSource $
         x { resultVectorItems =
                A.array bnds [(i, resultSourceSummary e) | (i, e) <- ies] } }
  where
    arr  = resultVectorItems x
    bnds = A.bounds arr
    ies  = A.assocs arr

-- | It separates the simulation results when printing.
data ResultSeparator =
  ResultSeparator { resultSeparatorText :: String
                    -- ^ The separator text.
                  }

-- | A parameterised value that actually represents a generalised result item that have no parametric type.
data ResultValue e m =
  ResultValue { resultValueName :: ResultName,
                -- ^ The value name.
                resultValueNamePath :: [ResultName],
                -- ^ The value name path.
                resultValueId :: ResultId,
                -- ^ The value identifier.
                resultValueIdPath :: [ResultId],
                -- ^ The value identifier path.
                resultValueData :: ResultData e m,
                -- ^ Simulation data supplied by the value.
                resultValueSignal :: ResultSignal m
                -- ^ Whether the value emits a signal when changing simulation data.
              }

-- | Map the result value according the specfied function.
mapResultValue :: MonadDES m => (a -> b) -> ResultValue a m -> ResultValue b m
mapResultValue f x = x { resultValueData = fmap f (resultValueData x) }

-- | Transform the result value.
apResultValue :: MonadDES m => ResultData (a -> b) m -> ResultValue a m -> ResultValue b m
apResultValue f x = x { resultValueData = ap f (resultValueData x) }

-- | A container of the simulation results such as queue, server or array.
data ResultContainer e m =
  ResultContainer { resultContainerName :: ResultName,
                    -- ^ The container name.
                    resultContainerNamePath :: [ResultName],
                    -- ^ The container name path.
                    resultContainerId :: ResultId,
                    -- ^ The container identifier.
                    resultContainerIdPath :: [ResultId],
                    -- ^ The container identifier path.
                    resultContainerData :: e,
                    -- ^ The container data.
                    resultContainerSignal :: ResultSignal m
                    -- ^ Whether the container emits a signal when changing simulation data.
                  }

mapResultContainer :: (a -> b) -> ResultContainer a m -> ResultContainer b m
mapResultContainer f x = x { resultContainerData = f (resultContainerData x) }

-- | Create a new property source by the specified container.
resultContainerPropertySource :: ResultItemable (ResultValue b)
                                 => ResultContainer a m
                                 -- ^ the container
                                 -> ResultName
                                 -- ^ the property label
                                 -> ResultId
                                 -- ^ the property identifier
                                 -> (a -> ResultData b m)
                                 -- ^ get the specified data from the container
                                 -> (a -> ResultSignal m)
                                 -- ^ get the data signal from the container
                                 -> ResultSource m
resultContainerPropertySource cont name i f g =
  ResultItemSource $
  ResultItem $
  ResultValue {
    resultValueName   = (resultContainerName cont) ++ "." ++ name,
    resultValueNamePath = (resultContainerNamePath cont) ++ [name],
    resultValueId     = i,
    resultValueIdPath = (resultContainerIdPath cont) ++ [i],
    resultValueData   = f (resultContainerData cont),
    resultValueSignal = g (resultContainerData cont) }

-- | Create a constant property by the specified container.
resultContainerConstProperty :: (MonadDES m,
                                 ResultItemable (ResultValue b))
                                => ResultContainer a m
                                -- ^ the container
                                -> ResultName
                                -- ^ the property label
                                -> ResultId
                                -- ^ the property identifier
                                -> (a -> b)
                                -- ^ get the specified data from the container
                                -> ResultProperty m
resultContainerConstProperty cont name i f =
  ResultProperty {
    resultPropertyLabel = name,
    resultPropertyId = i,
    resultPropertySource =
      resultContainerPropertySource cont name i (return . f) (const EmptyResultSignal) }
  
-- | Create by the specified container a property that changes in the integration time points, or it is supposed to be such one.
resultContainerIntegProperty :: (MonadDES m,
                                 ResultItemable (ResultValue b))
                                => ResultContainer a m
                                -- ^ the container
                                -> ResultName
                                -- ^ the property label
                                -> ResultId
                                -- ^ the property identifier
                                -> (a -> Event m b)
                                -- ^ get the specified data from the container
                                -> ResultProperty m
resultContainerIntegProperty cont name i f =
  ResultProperty {
    resultPropertyLabel = name,
    resultPropertyId = i,
    resultPropertySource =
      resultContainerPropertySource cont name i f (const UnknownResultSignal) }
  
-- | Create a property by the specified container.
resultContainerProperty :: (MonadDES m,
                            ResultItemable (ResultValue b))
                           => ResultContainer a m
                           -- ^ the container
                           -> ResultName
                           -- ^ the property label
                           -> ResultId
                           -- ^ the property identifier
                           -> (a -> Event m b)
                           -- ^ get the specified data from the container
                           -> (a -> Signal m ())
                           -- ^ get a signal triggered when changing data.
                           -> ResultProperty m
resultContainerProperty cont name i f g =                     
  ResultProperty {
    resultPropertyLabel = name,
    resultPropertyId = i,
    resultPropertySource =
      resultContainerPropertySource cont name i f (ResultSignal . g) }

-- | Create by the specified container a mapped property which is recomputed each time again and again.
resultContainerMapProperty :: (MonadDES m,
                               ResultItemable (ResultValue b))
                              => ResultContainer (ResultData a m) m
                              -- ^ the container
                              -> ResultName
                              -- ^ the property label
                              -> ResultId
                              -- ^ the property identifier
                              -> (a -> b)
                              -- ^ recompute the specified data
                              -> ResultProperty m
resultContainerMapProperty cont name i f =                     
  ResultProperty {
    resultPropertyLabel = name,
    resultPropertyId = i,
    resultPropertySource =
      resultContainerPropertySource cont name i (fmap f) (const $ resultContainerSignal cont) }

-- | Convert the result value to a container with the specified object identifier. 
resultValueToContainer :: ResultValue a m -> ResultContainer (ResultData a m) m
resultValueToContainer x =
  ResultContainer {
    resultContainerName   = resultValueName x,
    resultContainerNamePath = resultValueNamePath x,
    resultContainerId     = resultValueId x,
    resultContainerIdPath = resultValueIdPath x,
    resultContainerData   = resultValueData x,
    resultContainerSignal = resultValueSignal x }

-- | Convert the result container to a value.
resultContainerToValue :: ResultContainer (ResultData a m) m -> ResultValue a m
resultContainerToValue x =
  ResultValue {
    resultValueName   = resultContainerName x,
    resultValueNamePath = resultContainerNamePath x,
    resultValueId     = resultContainerId x,
    resultValueIdPath = resultContainerIdPath x,
    resultValueData   = resultContainerData x,
    resultValueSignal = resultContainerSignal x }

-- | Represents the very simulation results.
type ResultData e m = Event m e

-- | Convert the timing statistics data to its normalised sampling-based representation.
normTimingStatsData :: (TimingData a, Monad m) => ResultData (TimingStats a -> SamplingStats a) m
normTimingStatsData =
  do n <- liftDynamics integIteration
     return $ normTimingStats (fromIntegral n)

-- | Whether an object containing the results emits a signal notifying about change of data.
data ResultSignal m = EmptyResultSignal
                      -- ^ There is no signal at all.
                    | UnknownResultSignal
                      -- ^ The signal is unknown, but the entity probably changes.
                    | ResultSignal (Signal m ())
                      -- ^ When the signal is precisely specified.
                    | ResultSignalMix (Signal m ())
                      -- ^ When the specified signal was combined with unknown signal.

instance MonadDES m => Monoid (ResultSignal m) where

  mempty = EmptyResultSignal

  mappend EmptyResultSignal z = z

  mappend UnknownResultSignal EmptyResultSignal = UnknownResultSignal
  mappend UnknownResultSignal UnknownResultSignal = UnknownResultSignal
  mappend UnknownResultSignal (ResultSignal x) = ResultSignalMix x
  mappend UnknownResultSignal z@(ResultSignalMix x) = z
  
  mappend z@(ResultSignal x) EmptyResultSignal = z
  mappend (ResultSignal x) UnknownResultSignal = ResultSignalMix x
  mappend (ResultSignal x) (ResultSignal y) = ResultSignal (x <> y)
  mappend (ResultSignal x) (ResultSignalMix y) = ResultSignalMix (x <> y)
  
  mappend z@(ResultSignalMix x) EmptyResultSignal = z
  mappend z@(ResultSignalMix x) UnknownResultSignal = z
  mappend (ResultSignalMix x) (ResultSignal y) = ResultSignalMix (x <> y)
  mappend (ResultSignalMix x) (ResultSignalMix y) = ResultSignalMix (x <> y)

-- | Construct a new result signal by the specified optional pure signal.
maybeResultSignal :: Maybe (Signal m ()) -> ResultSignal m
maybeResultSignal (Just x) = ResultSignal x
maybeResultSignal Nothing  = EmptyResultSignal

instance ResultItemable (ResultValue Int) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = Just
  resultItemAsIntListValue = Just . mapResultValue return
  resultItemAsIntStatsValue = Just . mapResultValue returnSamplingStats
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = Just . mapResultValue fromIntegral
  resultItemAsDoubleListValue = Just . mapResultValue (return . fromIntegral)
  resultItemAsDoubleStatsValue = Just . mapResultValue (returnSamplingStats . fromIntegral)
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show

  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

instance ResultItemable (ResultValue Double) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing
  
  resultItemAsDoubleValue = Just
  resultItemAsDoubleListValue = Just . mapResultValue return
  resultItemAsDoubleStatsValue = Just . mapResultValue returnSamplingStats
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show
  
  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

instance ResultItemable (ResultValue [Int]) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = Just
  resultItemAsIntStatsValue = Just . mapResultValue listSamplingStats
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = Just . mapResultValue (map fromIntegral)
  resultItemAsDoubleStatsValue = Just . mapResultValue (fromIntSamplingStats . listSamplingStats)
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show
  
  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

instance ResultItemable (ResultValue [Double]) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing
  
  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = Just
  resultItemAsDoubleStatsValue = Just . mapResultValue listSamplingStats
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show
  
  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

instance ResultItemable (ResultValue (SamplingStats Int)) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = Just
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = Just . mapResultValue fromIntSamplingStats
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show
  
  resultItemExpansion = samplingStatsResultSource
  resultItemSummary = samplingStatsResultSummary

instance ResultItemable (ResultValue (SamplingStats Double)) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing
  
  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = Just
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show
  
  resultItemExpansion = samplingStatsResultSource
  resultItemSummary = samplingStatsResultSummary

instance ResultItemable (ResultValue (TimingStats Int)) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = Just . apResultValue normTimingStatsData
  resultItemAsIntTimingStatsValue = Just

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = Just . mapResultValue fromIntSamplingStats . apResultValue normTimingStatsData
  resultItemAsDoubleTimingStatsValue = Just . mapResultValue fromIntTimingStats

  resultItemAsStringValue = Just . mapResultValue show
  
  resultItemExpansion = timingStatsResultSource
  resultItemSummary = timingStatsResultSummary

instance ResultItemable (ResultValue  (TimingStats Double)) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = Just . apResultValue normTimingStatsData
  resultItemAsDoubleTimingStatsValue = Just

  resultItemAsStringValue = Just . mapResultValue show
  
  resultItemExpansion = timingStatsResultSource
  resultItemSummary = timingStatsResultSummary

instance ResultItemable (ResultValue Bool) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = const Nothing
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show

  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

instance ResultItemable (ResultValue String) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = const Nothing
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just

  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

instance ResultItemable (ResultValue ()) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = const Nothing
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show

  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

instance ResultItemable (ResultValue FCFS) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = const Nothing
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show

  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

instance ResultItemable (ResultValue LCFS) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = const Nothing
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show

  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

instance ResultItemable (ResultValue SIRO) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = const Nothing
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show

  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

instance ResultItemable (ResultValue StaticPriorities) where

  resultItemName = resultValueName
  resultItemNamePath = resultValueNamePath
  resultItemId = resultValueId
  resultItemIdPath = resultValueIdPath
  resultItemSignal = resultValueSignal
  
  resultItemAsIntValue = const Nothing
  resultItemAsIntListValue = const Nothing
  resultItemAsIntStatsValue = const Nothing
  resultItemAsIntTimingStatsValue = const Nothing

  resultItemAsDoubleValue = const Nothing
  resultItemAsDoubleListValue = const Nothing
  resultItemAsDoubleStatsValue = const Nothing
  resultItemAsDoubleTimingStatsValue = const Nothing

  resultItemAsStringValue = Just . mapResultValue show

  resultItemExpansion = ResultItemSource . ResultItem
  resultItemSummary = ResultItemSource . ResultItem

-- | Flatten the result source.
flattenResultSource :: ResultSource m -> [ResultItem m]
flattenResultSource (ResultItemSource x) = [x]
flattenResultSource (ResultObjectSource x) =
  concat $ map (flattenResultSource . resultPropertySource) $ resultObjectProperties x
flattenResultSource (ResultVectorSource x) =
  concat $ map flattenResultSource $ A.elems $ resultVectorItems x
flattenResultSource (ResultSeparatorSource x) = []

-- | Return the result source name.
resultSourceName :: ResultSource m -> ResultName
resultSourceName (ResultItemSource (ResultItem x)) = resultItemName x
resultSourceName (ResultObjectSource x) = resultObjectName x
resultSourceName (ResultVectorSource x) = resultVectorName x
resultSourceName (ResultSeparatorSource x) = []

-- | Expand the result source returning a more detailed version expanding the properties as possible.
expandResultSource :: MonadDES m => ResultSource m -> ResultSource m
expandResultSource (ResultItemSource (ResultItem x)) = resultItemExpansion x
expandResultSource (ResultObjectSource x) =
  ResultObjectSource $
  x { resultObjectProperties =
         flip fmap (resultObjectProperties x) $ \p ->
         p { resultPropertySource = expandResultSource (resultPropertySource p) } }
expandResultSource (ResultVectorSource x) =
  ResultVectorSource $
  x { resultVectorItems =
         A.array bnds [(i, expandResultSource e) | (i, e) <- ies] }
    where arr  = resultVectorItems x
          bnds = A.bounds arr
          ies  = A.assocs arr
expandResultSource z@(ResultSeparatorSource x) = z

-- | Return a summarised and usually more short version of the result source expanding the main properties or excluding auxiliary properties if required.
resultSourceSummary :: MonadDES m => ResultSource m -> ResultSource m
resultSourceSummary (ResultItemSource (ResultItem x)) = resultItemSummary x
resultSourceSummary (ResultObjectSource x) = resultObjectSummary x
resultSourceSummary (ResultVectorSource x) = resultVectorSummary x
resultSourceSummary z@(ResultSeparatorSource x) = z

-- | Return a signal emitted by the source.
resultSourceSignal :: MonadDES m => ResultSource m -> ResultSignal m
resultSourceSignal (ResultItemSource (ResultItem x)) = resultItemSignal x
resultSourceSignal (ResultObjectSource x) = resultObjectSignal x
resultSourceSignal (ResultVectorSource x) = resultVectorSignal x
resultSourceSignal (ResultSeparatorSource x) = EmptyResultSignal

-- | Represent the result source as integer numbers.
resultSourceToIntValues :: MonadDES m => ResultSource m -> [ResultValue Int m]
resultSourceToIntValues = map (\(ResultItem x) -> resultItemToIntValue x) . flattenResultSource

-- | Represent the result source as lists of integer numbers.
resultSourceToIntListValues :: MonadDES m => ResultSource m -> [ResultValue [Int] m]
resultSourceToIntListValues = map (\(ResultItem x) -> resultItemToIntListValue x) . flattenResultSource

-- | Represent the result source as statistics based on integer numbers.
resultSourceToIntStatsValues :: MonadDES m => ResultSource m -> [ResultValue (SamplingStats Int) m]
resultSourceToIntStatsValues = map (\(ResultItem x) -> resultItemToIntStatsValue x) . flattenResultSource

-- | Represent the result source as statistics based on integer numbers and optimised for fast aggregation.
resultSourceToIntStatsEitherValues :: MonadDES m => ResultSource m -> [ResultValue (Either Int (SamplingStats Int)) m]
resultSourceToIntStatsEitherValues = map (\(ResultItem x) -> resultItemToIntStatsEitherValue x) . flattenResultSource

-- | Represent the result source as timing statistics based on integer numbers.
resultSourceToIntTimingStatsValues :: MonadDES m => ResultSource m -> [ResultValue (TimingStats Int) m]
resultSourceToIntTimingStatsValues = map (\(ResultItem x) -> resultItemToIntTimingStatsValue x) . flattenResultSource

-- | Represent the result source as double floating point numbers.
resultSourceToDoubleValues :: MonadDES m => ResultSource m -> [ResultValue Double m]
resultSourceToDoubleValues = map (\(ResultItem x) -> resultItemToDoubleValue x) . flattenResultSource

-- | Represent the result source as lists of double floating point numbers.
resultSourceToDoubleListValues :: MonadDES m => ResultSource m -> [ResultValue [Double] m]
resultSourceToDoubleListValues = map (\(ResultItem x) -> resultItemToDoubleListValue x) . flattenResultSource

-- | Represent the result source as statistics based on double floating point numbers.
resultSourceToDoubleStatsValues :: MonadDES m => ResultSource m -> [ResultValue (SamplingStats Double) m]
resultSourceToDoubleStatsValues = map (\(ResultItem x) -> resultItemToDoubleStatsValue x) . flattenResultSource

-- | Represent the result source as statistics based on double floating point numbers and optimised for fast aggregation.
resultSourceToDoubleStatsEitherValues :: MonadDES m => ResultSource m -> [ResultValue (Either Double (SamplingStats Double)) m]
resultSourceToDoubleStatsEitherValues = map (\(ResultItem x) -> resultItemToDoubleStatsEitherValue x) . flattenResultSource

-- | Represent the result source as timing statistics based on double floating point numbers.
resultSourceToDoubleTimingStatsValues :: MonadDES m => ResultSource m -> [ResultValue (TimingStats Double) m]
resultSourceToDoubleTimingStatsValues = map (\(ResultItem x) -> resultItemToDoubleTimingStatsValue x) . flattenResultSource

-- | Represent the result source as string values.
resultSourceToStringValues :: MonadDES m => ResultSource m -> [ResultValue String m]
resultSourceToStringValues = map (\(ResultItem x) -> resultItemToStringValue x) . flattenResultSource

-- | It contains the results of simulation.
data Results m =
  Results { resultSourceMap :: ResultSourceMap m,
            -- ^ The sources of simulation results as a map of associated names.
            resultSourceList :: [ResultSource m]
            -- ^ The sources of simulation results as an ordered list.
          }

-- | It transforms the results of simulation.
type ResultTransform m = Results m -> Results m

-- | It representes the predefined signals provided by every simulation model.
data ResultPredefinedSignals m =
  ResultPredefinedSignals { resultSignalInIntegTimes :: Signal m Double,
                            -- ^ The signal triggered in the integration time points.
                            resultSignalInStartTime :: Signal m Double,
                            -- ^ The signal triggered in the start time.
                            resultSignalInStopTime :: Signal m Double
                            -- ^ The signal triggered in the stop time.
                          }

-- | Create the predefined signals provided by every simulation model.
newResultPredefinedSignals :: MonadDES m => Simulation m (ResultPredefinedSignals m)
newResultPredefinedSignals = runDynamicsInStartTime $ runEventWith EarlierEvents d where
  d = do signalInIntegTimes <- newSignalInIntegTimes
         signalInStartTime  <- newSignalInStartTime
         signalInStopTime   <- newSignalInStopTime
         return ResultPredefinedSignals { resultSignalInIntegTimes = signalInIntegTimes,
                                          resultSignalInStartTime  = signalInStartTime,
                                          resultSignalInStopTime   = signalInStopTime }

instance Monoid (Results m) where

  mempty      = results mempty
  mappend x y = results $ resultSourceList x <> resultSourceList y

-- | Prepare the simulation results.
results :: [ResultSource m] -> Results m
results ms =
  Results { resultSourceMap  = M.fromList $ map (\x -> (resultSourceName x, x)) ms,
            resultSourceList = ms }

-- | Represent the results as integer numbers.
resultsToIntValues :: MonadDES m => Results m -> [ResultValue Int m]
resultsToIntValues = concat . map resultSourceToIntValues . resultSourceList

-- | Represent the results as lists of integer numbers.
resultsToIntListValues :: MonadDES m => Results m -> [ResultValue [Int] m]
resultsToIntListValues = concat . map resultSourceToIntListValues . resultSourceList

-- | Represent the results as statistics based on integer numbers.
resultsToIntStatsValues :: MonadDES m => Results m -> [ResultValue (SamplingStats Int) m]
resultsToIntStatsValues = concat . map resultSourceToIntStatsValues . resultSourceList

-- | Represent the results as statistics based on integer numbers and optimised for fast aggregation.
resultsToIntStatsEitherValues :: MonadDES m => Results m -> [ResultValue (Either Int (SamplingStats Int)) m]
resultsToIntStatsEitherValues = concat . map resultSourceToIntStatsEitherValues . resultSourceList

-- | Represent the results as timing statistics based on integer numbers.
resultsToIntTimingStatsValues :: MonadDES m => Results m -> [ResultValue (TimingStats Int) m]
resultsToIntTimingStatsValues = concat . map resultSourceToIntTimingStatsValues . resultSourceList

-- | Represent the results as double floating point numbers.
resultsToDoubleValues :: MonadDES m => Results m -> [ResultValue Double m]
resultsToDoubleValues = concat . map resultSourceToDoubleValues . resultSourceList

-- | Represent the results as lists of double floating point numbers.
resultsToDoubleListValues :: MonadDES m => Results m -> [ResultValue [Double] m]
resultsToDoubleListValues = concat . map resultSourceToDoubleListValues . resultSourceList

-- | Represent the results as statistics based on double floating point numbers.
resultsToDoubleStatsValues :: MonadDES m => Results m -> [ResultValue (SamplingStats Double) m]
resultsToDoubleStatsValues = concat . map resultSourceToDoubleStatsValues . resultSourceList

-- | Represent the results as statistics based on double floating point numbers and optimised for fast aggregation.
resultsToDoubleStatsEitherValues :: MonadDES m => Results m -> [ResultValue (Either Double (SamplingStats Double)) m]
resultsToDoubleStatsEitherValues = concat . map resultSourceToDoubleStatsEitherValues . resultSourceList

-- | Represent the results as timing statistics based on double floating point numbers.
resultsToDoubleTimingStatsValues :: MonadDES m => Results m -> [ResultValue (TimingStats Double) m]
resultsToDoubleTimingStatsValues = concat . map resultSourceToDoubleTimingStatsValues . resultSourceList

-- | Represent the results as string values.
resultsToStringValues :: MonadDES m => Results m -> [ResultValue String m]
resultsToStringValues = concat . map resultSourceToStringValues . resultSourceList

-- | Return a signal emitted by the specified results.
resultSignal :: MonadDES m => Results m -> ResultSignal m
resultSignal = mconcat . map resultSourceSignal . resultSourceList

-- | Return an expanded version of the simulation results expanding the properties as possible, which
-- takes place for expanding statistics to show the count, average, deviation, minimum, maximum etc.
-- as separate values.
expandResults :: MonadDES m => ResultTransform m
expandResults = results . map expandResultSource . resultSourceList

-- | Return a short version of the simulation results, i.e. their summary, expanding the main properties
-- or excluding auxiliary properties if required.
resultSummary :: MonadDES m => ResultTransform m
resultSummary = results . map resultSourceSummary . resultSourceList

-- | Take a result by its name.
resultByName :: ResultName -> ResultTransform m
resultByName name rs =
  case M.lookup name (resultSourceMap rs) of
    Just x -> results [x]
    Nothing ->
      error $
      "Not found result source with name " ++ name ++
      ": resultByName"

-- | Take a result from the object with the specified property label,
-- but it is more preferrable to refer to the property by its 'ResultId'
-- identifier with help of the 'resultById' function.
resultByProperty :: ResultName -> ResultTransform m
resultByProperty label rs = flip composeResults rs loop
  where
    loop x =
      case x of
        ResultObjectSource s ->
          let ps =
                flip filter (resultObjectProperties s) $ \p ->
                resultPropertyLabel p == label
          in case ps of
            [] ->
              error $
              "Not found property " ++ label ++
              " for object " ++ resultObjectName s ++
              ": resultByProperty"
            ps ->
              map resultPropertySource ps
        ResultVectorSource s ->
          concat $ map loop $ A.elems $ resultVectorItems s
        x ->
          error $
          "Result source " ++ resultSourceName x ++
          " is neither object, nor vector " ++
          ": resultByProperty"

-- | Take a result from the object with the specified identifier. It can identify
-- an item, object property, the object iself, vector or its elements.
resultById :: ResultId -> ResultTransform m
resultById i rs = flip composeResults rs loop
  where
    loop x =
      case x of
        ResultItemSource (ResultItem s) ->
          if resultItemId s == i
          then [x]
          else error $
               "Expected to find item with Id = " ++ show i ++
               ", while the item " ++ resultItemName s ++
               " has actual Id = " ++ show (resultItemId s) ++
               ": resultById"
        ResultObjectSource s ->
          if resultObjectId s == i
          then [x]
          else let ps =
                     flip filter (resultObjectProperties s) $ \p ->
                     resultPropertyId p == i
               in case ps of
                 [] ->
                   error $
                   "Not found property with Id = " ++ show i ++
                   " for object " ++ resultObjectName s ++
                   " that has actual Id = " ++ show (resultObjectId s) ++
                   ": resultById"
                 ps ->
                   map resultPropertySource ps
        ResultVectorSource s ->
          if resultVectorId s == i
          then [x]
          else concat $ map loop $ A.elems $ resultVectorItems s
        x ->
          error $
          "Result source " ++ resultSourceName x ++
          " is neither item, nor object, nor vector " ++
          ": resultById"

-- | Take a result from the vector by the specified integer index.
resultByIndex :: Int -> ResultTransform m
resultByIndex index rs = flip composeResults rs loop
  where
    loop x =
      case x of
        ResultVectorSource s ->
          [resultVectorItems s A.! index] 
        x ->
          error $
          "Result source " ++ resultSourceName x ++
          " is not vector " ++
          ": resultByIndex"

-- | Take a result from the vector by the specified string subscript.
resultBySubscript :: ResultName -> ResultTransform m
resultBySubscript subscript rs = flip composeResults rs loop
  where
    loop x =
      case x of
        ResultVectorSource s ->
          let ys = A.elems $ resultVectorItems s
              zs = A.elems $ resultVectorSubscript s
              ps =
                flip filter (zip ys zs) $ \(y, z) ->
                z == subscript
          in case ps of
            [] ->
              error $
              "Not found subscript " ++ subscript ++
              " for vector " ++ resultVectorName s ++
              ": resultBySubscript"
            ps ->
              map fst ps
        x ->
          error $
          "Result source " ++ resultSourceName x ++
          " is not vector " ++
          ": resultBySubscript"

-- | Compose the results using the specified transformation function.
composeResults :: (ResultSource m -> [ResultSource m]) -> ResultTransform m
composeResults f =
  results . concat . map f . resultSourceList

-- | Concatenate the results using the specified list of transformation functions.
concatResults :: [ResultTransform m] -> ResultTransform m
concatResults trs rs =
  results $ concat $ map (\tr -> resultSourceList $ tr rs) trs

-- | Append the results using the specified transformation functions.
appendResults :: ResultTransform m -> ResultTransform m -> ResultTransform m
appendResults x y =
  concatResults [x, y]

-- | Return a pure signal as a result of combination of the predefined signals
-- with the specified result signal usually provided by the sources.
--
-- The signal returned is triggered when the source signal is triggered.
-- The pure signal is also triggered in the integration time points
-- if the source signal is unknown or it was combined with any unknown signal.
pureResultSignal :: MonadDES m => ResultPredefinedSignals m -> ResultSignal m -> Signal m ()
pureResultSignal rs EmptyResultSignal =
  void (resultSignalInStartTime rs)
pureResultSignal rs UnknownResultSignal =
  void (resultSignalInIntegTimes rs)
pureResultSignal rs (ResultSignal s) =
  void (resultSignalInStartTime rs) <> void (resultSignalInStopTime rs) <> s
pureResultSignal rs (ResultSignalMix s) =
  void (resultSignalInIntegTimes rs) <> s

-- | Represents a computation that can return the simulation data.
class MonadDES m => ResultComputing t m where

  -- | Compute data with the results of simulation.
  computeResultData :: t m a -> ResultData a m

  -- | Return the signal triggered when data change if such a signal exists.
  computeResultSignal :: t m a -> ResultSignal m

-- | Return a new result value by the specified name, identifier and computation.
computeResultValue :: ResultComputing t m
                      => ResultName
                      -- ^ the result name
                      -> [ResultName]
                      -- ^ the result name path
                      -> ResultId
                      -- ^ the result identifier
                      -> [ResultId]
                      -- ^ the result identifier path
                      -> t m a
                      -- ^ the result computation
                      -> ResultValue a m
computeResultValue name names i is m =
  ResultValue {
    resultValueName   = name,
    resultValueNamePath = names,
    resultValueId     = i,
    resultValueIdPath = is,
    resultValueData   = computeResultData m,
    resultValueSignal = computeResultSignal m }

instance MonadDES m => ResultComputing Parameter m where

  computeResultData = liftParameter
  computeResultSignal = const UnknownResultSignal

instance MonadDES m => ResultComputing Simulation m where

  computeResultData = liftSimulation
  computeResultSignal = const UnknownResultSignal

instance MonadDES m => ResultComputing Dynamics m where

  computeResultData = liftDynamics
  computeResultSignal = const UnknownResultSignal

instance MonadDES m => ResultComputing Event m where

  computeResultData = id
  computeResultSignal = const UnknownResultSignal

instance MonadDES m => ResultComputing Ref m where

  computeResultData = readRef
  computeResultSignal = ResultSignal . refChanged_

instance MonadDES m => ResultComputing B.Ref m where

  computeResultData = B.readRef
  computeResultSignal = const UnknownResultSignal

instance MonadVar m => ResultComputing Var m where

  computeResultData = readVar
  computeResultSignal = ResultSignal . varChanged_

instance MonadDES m => ResultComputing Signalable m where

  computeResultData = readSignalable
  computeResultSignal = ResultSignal . signalableChanged_
      
-- | Return a source by the specified statistics.
samplingStatsResultSource :: (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (SamplingStats a)))
                             => ResultValue (SamplingStats a) m
                             -- ^ the statistics
                             -> ResultSource m
samplingStatsResultSource x =
  ResultObjectSource $
  ResultObject {
    resultObjectName      = resultValueName x,
    resultObjectId        = resultValueId x,
    resultObjectTypeId    = SamplingStatsId,
    resultObjectSignal    = resultValueSignal x,
    resultObjectSummary   = samplingStatsResultSummary x,
    resultObjectProperties = [
      resultContainerMapProperty c "count" SamplingStatsCountId samplingStatsCount,
      resultContainerMapProperty c "mean" SamplingStatsMeanId samplingStatsMean,
      resultContainerMapProperty c "mean2" SamplingStatsMean2Id samplingStatsMean2,
      resultContainerMapProperty c "std" SamplingStatsDeviationId samplingStatsDeviation,
      resultContainerMapProperty c "var" SamplingStatsVarianceId samplingStatsVariance,
      resultContainerMapProperty c "min" SamplingStatsMinId samplingStatsMin,
      resultContainerMapProperty c "max" SamplingStatsMaxId samplingStatsMax ] }
  where
    c = resultValueToContainer x

-- | Return the summary by the specified statistics.
samplingStatsResultSummary :: (MonadDES m,
                               ResultItemable (ResultValue (SamplingStats a)))
                              => ResultValue (SamplingStats a) m
                              -- ^ the statistics
                              -> ResultSource m
samplingStatsResultSummary = ResultItemSource . ResultItem . resultItemToStringValue 
  
-- | Return a source by the specified timing statistics.
timingStatsResultSource :: (MonadDES m,
                            TimingData a,
                            ResultItemable (ResultValue a),
                            ResultItemable (ResultValue (TimingStats a)))
                           => ResultValue (TimingStats a) m
                           -- ^ the statistics
                           -> ResultSource m
timingStatsResultSource x =
  ResultObjectSource $
  ResultObject {
    resultObjectName      = resultValueName x,
    resultObjectId        = resultValueId x,
    resultObjectTypeId    = TimingStatsId,
    resultObjectSignal    = resultValueSignal x,
    resultObjectSummary   = timingStatsResultSummary x,
    resultObjectProperties = [
      resultContainerMapProperty c "count" TimingStatsCountId timingStatsCount,
      resultContainerMapProperty c "mean" TimingStatsMeanId timingStatsMean,
      resultContainerMapProperty c "std" TimingStatsDeviationId timingStatsDeviation,
      resultContainerMapProperty c "var" TimingStatsVarianceId timingStatsVariance,
      resultContainerMapProperty c "min" TimingStatsMinId timingStatsMin,
      resultContainerMapProperty c "max" TimingStatsMaxId timingStatsMax,
      resultContainerMapProperty c "minTime" TimingStatsMinTimeId timingStatsMinTime,
      resultContainerMapProperty c "maxTime" TimingStatsMaxTimeId timingStatsMaxTime,
      resultContainerMapProperty c "startTime" TimingStatsStartTimeId timingStatsStartTime,
      resultContainerMapProperty c "lastTime" TimingStatsLastTimeId timingStatsLastTime,
      resultContainerMapProperty c "sum" TimingStatsSumId timingStatsSum,
      resultContainerMapProperty c "sum2" TimingStatsSum2Id timingStatsSum2 ] }
  where
    c = resultValueToContainer x

-- | Return the summary by the specified timing statistics.
timingStatsResultSummary :: (MonadDES m,
                             TimingData a,
                             ResultItemable (ResultValue (TimingStats a)))
                            => ResultValue (TimingStats a) m 
                            -- ^ the statistics
                            -> ResultSource m
timingStatsResultSummary = ResultItemSource . ResultItem . resultItemToStringValue
  
-- | Return a source by the specified counter.
samplingCounterResultSource :: (MonadDES m,
                                ResultItemable (ResultValue a),
                                ResultItemable (ResultValue (SamplingStats a)))
                               => ResultValue (SamplingCounter a) m
                               -- ^ the counter
                               -> ResultSource m
samplingCounterResultSource x =
  ResultObjectSource $
  ResultObject {
    resultObjectName      = resultValueName x,
    resultObjectId        = resultValueId x,
    resultObjectTypeId    = SamplingCounterId,
    resultObjectSignal    = resultValueSignal x,
    resultObjectSummary   = samplingCounterResultSummary x,
    resultObjectProperties = [
      resultContainerMapProperty c "value" SamplingCounterValueId samplingCounterValue,
      resultContainerMapProperty c "stats" SamplingCounterStatsId samplingCounterStats ] }
  where
    c = resultValueToContainer x
      
-- | Return a source by the specified counter.
samplingCounterResultSummary :: (MonadDES m,
                                 ResultItemable (ResultValue a),
                                 ResultItemable (ResultValue (SamplingStats a)))
                                => ResultValue (SamplingCounter a) m
                                -- ^ the counter
                                -> ResultSource m
samplingCounterResultSummary x =
  ResultObjectSource $
  ResultObject {
    resultObjectName      = resultValueName x,
    resultObjectId        = resultValueId x,
    resultObjectTypeId    = SamplingCounterId,
    resultObjectSignal    = resultValueSignal x,
    resultObjectSummary   = samplingCounterResultSummary x,
    resultObjectProperties = [
      resultContainerMapProperty c "value" SamplingCounterValueId samplingCounterValue,
      resultContainerMapProperty c "stats" SamplingCounterStatsId samplingCounterStats ] }
  where
    c = resultValueToContainer x
      
-- | Return a source by the specified counter.
timingCounterResultSource :: (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (TimingStats a)))
                             => ResultValue (TimingCounter a) m
                             -- ^ the counter
                             -> ResultSource m
timingCounterResultSource x =
  ResultObjectSource $
  ResultObject {
    resultObjectName      = resultValueName x,
    resultObjectId        = resultValueId x,
    resultObjectTypeId    = TimingCounterId,
    resultObjectSignal    = resultValueSignal x,
    resultObjectSummary   = timingCounterResultSummary x,
    resultObjectProperties = [
      resultContainerMapProperty c "value" TimingCounterValueId timingCounterValue,
      resultContainerMapProperty c "stats" TimingCounterStatsId timingCounterStats ] }
  where
    c = resultValueToContainer x
      
-- | Return a source by the specified counter.
timingCounterResultSummary :: (MonadDES m,
                               ResultItemable (ResultValue a),
                               ResultItemable (ResultValue (TimingStats a)))
                              => ResultValue (TimingCounter a) m
                              -- ^ the counter
                              -> ResultSource m
timingCounterResultSummary x =
  ResultObjectSource $
  ResultObject {
    resultObjectName      = resultValueName x,
    resultObjectId        = resultValueId x,
    resultObjectTypeId    = TimingCounterId,
    resultObjectSignal    = resultValueSignal x,
    resultObjectSummary   = timingCounterResultSummary x,
    resultObjectProperties = [
      resultContainerMapProperty c "value" TimingCounterValueId timingCounterValue,
      resultContainerMapProperty c "stats" TimingCounterStatsId timingCounterStats ] }
  where
    c = resultValueToContainer x
  
-- | Return a source by the specified finite queue.
queueResultSource :: (MonadDES m,
                      Show si, Show sm, Show so,
                      ResultItemable (ResultValue si),
                      ResultItemable (ResultValue sm),
                      ResultItemable (ResultValue so))
                     => ResultContainer (Q.Queue m si sm so a) m
                     -- ^ the queue container
                     -> ResultSource m
queueResultSource c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = FiniteQueueId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = queueResultSummary c,
    resultObjectProperties = [
      resultContainerConstProperty c "enqueueStrategy" EnqueueStrategyId Q.enqueueStrategy,
      resultContainerConstProperty c "enqueueStoringStrategy" EnqueueStoringStrategyId Q.enqueueStoringStrategy,
      resultContainerConstProperty c "dequeueStrategy" DequeueStrategyId Q.dequeueStrategy,
      resultContainerProperty c "queueNull" QueueNullId Q.queueNull Q.queueNullChanged_,
      resultContainerProperty c "queueFull" QueueFullId Q.queueFull Q.queueFullChanged_,
      resultContainerConstProperty c "queueMaxCount" QueueMaxCountId Q.queueMaxCount,
      resultContainerProperty c "queueCount" QueueCountId Q.queueCount Q.queueCountChanged_,
      resultContainerProperty c "queueCountStats" QueueCountStatsId Q.queueCountStats Q.queueCountChanged_,
      resultContainerProperty c "enqueueCount" EnqueueCountId Q.enqueueCount Q.enqueueCountChanged_,
      resultContainerProperty c "enqueueLostCount" EnqueueLostCountId Q.enqueueLostCount Q.enqueueLostCountChanged_,
      resultContainerProperty c "enqueueStoreCount" EnqueueStoreCountId Q.enqueueStoreCount Q.enqueueStoreCountChanged_,
      resultContainerProperty c "dequeueCount" DequeueCountId Q.dequeueCount Q.dequeueCountChanged_,
      resultContainerProperty c "dequeueExtractCount" DequeueExtractCountId Q.dequeueExtractCount Q.dequeueExtractCountChanged_,
      resultContainerProperty c "queueLoadFactor" QueueLoadFactorId Q.queueLoadFactor Q.queueLoadFactorChanged_,
      resultContainerIntegProperty c "enqueueRate" EnqueueRateId Q.enqueueRate,
      resultContainerIntegProperty c "enqueueStoreRate" EnqueueStoreRateId Q.enqueueStoreRate,
      resultContainerIntegProperty c "dequeueRate" DequeueRateId Q.dequeueRate,
      resultContainerIntegProperty c "dequeueExtractRate" DequeueExtractRateId Q.dequeueExtractRate,
      resultContainerProperty c "queueWaitTime" QueueWaitTimeId Q.queueWaitTime Q.queueWaitTimeChanged_,
      resultContainerProperty c "queueTotalWaitTime" QueueTotalWaitTimeId Q.queueTotalWaitTime Q.queueTotalWaitTimeChanged_,
      resultContainerProperty c "enqueueWaitTime" EnqueueWaitTimeId Q.enqueueWaitTime Q.enqueueWaitTimeChanged_,
      resultContainerProperty c "dequeueWaitTime" DequeueWaitTimeId Q.dequeueWaitTime Q.dequeueWaitTimeChanged_,
      resultContainerProperty c "queueRate" QueueRateId Q.queueRate Q.queueRateChanged_ ] }

-- | Return the summary by the specified finite queue.
queueResultSummary :: (MonadDES m,
                       Show si, Show sm, Show so)
                      => ResultContainer (Q.Queue m si sm so a) m
                      -- ^ the queue container
                      -> ResultSource m
queueResultSummary c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = FiniteQueueId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = queueResultSummary c,
    resultObjectProperties = [
      resultContainerConstProperty c "queueMaxCount" QueueMaxCountId Q.queueMaxCount,
      resultContainerProperty c "queueCountStats" QueueCountStatsId Q.queueCountStats Q.queueCountChanged_,
      resultContainerProperty c "enqueueCount" EnqueueCountId Q.enqueueCount Q.enqueueCountChanged_,
      resultContainerProperty c "enqueueLostCount" EnqueueLostCountId Q.enqueueLostCount Q.enqueueLostCountChanged_,
      resultContainerProperty c "enqueueStoreCount" EnqueueStoreCountId Q.enqueueStoreCount Q.enqueueStoreCountChanged_,
      resultContainerProperty c "dequeueCount" DequeueCountId Q.dequeueCount Q.dequeueCountChanged_,
      resultContainerProperty c "dequeueExtractCount" DequeueExtractCountId Q.dequeueExtractCount Q.dequeueExtractCountChanged_,
      resultContainerProperty c "queueLoadFactor" QueueLoadFactorId Q.queueLoadFactor Q.queueLoadFactorChanged_,
      resultContainerProperty c "queueWaitTime" QueueWaitTimeId Q.queueWaitTime Q.queueWaitTimeChanged_,
      resultContainerProperty c "queueRate" QueueRateId Q.queueRate Q.queueRateChanged_ ] }

-- | Return a source by the specified infinite queue.
infiniteQueueResultSource :: (MonadDES m,
                              Show sm, Show so,
                              ResultItemable (ResultValue sm),
                              ResultItemable (ResultValue so))
                             => ResultContainer (IQ.Queue m sm so a) m
                             -- ^ the queue container
                             -> ResultSource m
infiniteQueueResultSource c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = FiniteQueueId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = infiniteQueueResultSummary c,
    resultObjectProperties = [
      resultContainerConstProperty c "enqueueStoringStrategy" EnqueueStoringStrategyId IQ.enqueueStoringStrategy,
      resultContainerConstProperty c "dequeueStrategy" DequeueStrategyId IQ.dequeueStrategy,
      resultContainerProperty c "queueNull" QueueNullId IQ.queueNull IQ.queueNullChanged_,
      resultContainerProperty c "queueCount" QueueCountId IQ.queueCount IQ.queueCountChanged_,
      resultContainerProperty c "queueCountStats" QueueCountStatsId IQ.queueCountStats IQ.queueCountChanged_,
      resultContainerProperty c "enqueueStoreCount" EnqueueStoreCountId IQ.enqueueStoreCount IQ.enqueueStoreCountChanged_,
      resultContainerProperty c "dequeueCount" DequeueCountId IQ.dequeueCount IQ.dequeueCountChanged_,
      resultContainerProperty c "dequeueExtractCount" DequeueExtractCountId IQ.dequeueExtractCount IQ.dequeueExtractCountChanged_,
      resultContainerIntegProperty c "enqueueStoreRate" EnqueueStoreRateId IQ.enqueueStoreRate,
      resultContainerIntegProperty c "dequeueRate" DequeueRateId IQ.dequeueRate,
      resultContainerIntegProperty c "dequeueExtractRate" DequeueExtractRateId IQ.dequeueExtractRate,
      resultContainerProperty c "queueWaitTime" QueueWaitTimeId IQ.queueWaitTime IQ.queueWaitTimeChanged_,
      resultContainerProperty c "dequeueWaitTime" DequeueWaitTimeId IQ.dequeueWaitTime IQ.dequeueWaitTimeChanged_,
      resultContainerProperty c "queueRate" QueueRateId IQ.queueRate IQ.queueRateChanged_ ] }

-- | Return the summary by the specified infinite queue.
infiniteQueueResultSummary :: (MonadDES m,
                               Show sm, Show so)
                              => ResultContainer (IQ.Queue m sm so a) m
                              -- ^ the queue container
                              -> ResultSource m
infiniteQueueResultSummary c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = FiniteQueueId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = infiniteQueueResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "queueCountStats" QueueCountStatsId IQ.queueCountStats IQ.queueCountChanged_,
      resultContainerProperty c "enqueueStoreCount" EnqueueStoreCountId IQ.enqueueStoreCount IQ.enqueueStoreCountChanged_,
      resultContainerProperty c "dequeueCount" DequeueCountId IQ.dequeueCount IQ.dequeueCountChanged_,
      resultContainerProperty c "dequeueExtractCount" DequeueExtractCountId IQ.dequeueExtractCount IQ.dequeueExtractCountChanged_,
      resultContainerProperty c "queueWaitTime" QueueWaitTimeId IQ.queueWaitTime IQ.queueWaitTimeChanged_,
      resultContainerProperty c "queueRate" QueueRateId IQ.queueRate IQ.queueRateChanged_ ] }
  
-- | Return a source by the specified arrival timer.
arrivalTimerResultSource :: MonadDES m
                            => ResultContainer (ArrivalTimer m) m
                            -- ^ the arrival timer container
                            -> ResultSource m
arrivalTimerResultSource c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = ArrivalTimerId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = arrivalTimerResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "processingTime" ArrivalProcessingTimeId arrivalProcessingTime arrivalProcessingTimeChanged_ ] }

-- | Return the summary by the specified arrival timer.
arrivalTimerResultSummary :: MonadDES m
                             => ResultContainer (ArrivalTimer m) m
                             -- ^ the arrival timer container
                             -> ResultSource m
arrivalTimerResultSummary c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = ArrivalTimerId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = arrivalTimerResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "processingTime" ArrivalProcessingTimeId arrivalProcessingTime arrivalProcessingTimeChanged_ ] }

-- | Return a source by the specified server.
serverResultSource :: (MonadDES m,
                       Show s, ResultItemable (ResultValue s))
                      => ResultContainer (Server m s a b) m
                      -- ^ the server container
                      -> ResultSource m
serverResultSource c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = ServerId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = serverResultSummary c,
    resultObjectProperties = [
      resultContainerConstProperty c "initState" ServerInitStateId serverInitState,
      resultContainerProperty c "state" ServerStateId serverState serverStateChanged_,
      resultContainerProperty c "totalInputWaitTime" ServerTotalInputWaitTimeId serverTotalInputWaitTime serverTotalInputWaitTimeChanged_,
      resultContainerProperty c "totalProcessingTime" ServerTotalProcessingTimeId serverTotalProcessingTime serverTotalProcessingTimeChanged_,
      resultContainerProperty c "totalOutputWaitTime" ServerTotalOutputWaitTimeId serverTotalOutputWaitTime serverTotalOutputWaitTimeChanged_,
      resultContainerProperty c "totalPreemptionTime" ServerTotalPreemptionTimeId serverTotalPreemptionTime serverTotalPreemptionTimeChanged_,
      resultContainerProperty c "inputWaitTime" ServerInputWaitTimeId serverInputWaitTime serverInputWaitTimeChanged_,
      resultContainerProperty c "processingTime" ServerProcessingTimeId serverProcessingTime serverProcessingTimeChanged_,
      resultContainerProperty c "outputWaitTime" ServerOutputWaitTimeId serverOutputWaitTime serverOutputWaitTimeChanged_,
      resultContainerProperty c "preemptionTime" ServerPreemptionTimeId serverPreemptionTime serverPreemptionTimeChanged_,
      resultContainerProperty c "inputWaitFactor" ServerInputWaitFactorId serverInputWaitFactor serverInputWaitFactorChanged_,
      resultContainerProperty c "processingFactor" ServerProcessingFactorId serverProcessingFactor serverProcessingFactorChanged_,
      resultContainerProperty c "outputWaitFactor" ServerOutputWaitFactorId serverOutputWaitFactor serverOutputWaitFactorChanged_,
      resultContainerProperty c "preemptionFactor" ServerPreemptionFactorId serverPreemptionFactor serverPreemptionFactorChanged_ ] }

-- | Return the summary by the specified server.
serverResultSummary :: MonadDES m
                       => ResultContainer (Server m s a b) m
                       -- ^ the server container
                       -> ResultSource m
serverResultSummary c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = ServerId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = serverResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "inputWaitTime" ServerInputWaitTimeId serverInputWaitTime serverInputWaitTimeChanged_,
      resultContainerProperty c "processingTime" ServerProcessingTimeId serverProcessingTime serverProcessingTimeChanged_,
      resultContainerProperty c "outputWaitTime" ServerOutputWaitTimeId serverOutputWaitTime serverOutputWaitTimeChanged_,
      resultContainerProperty c "preemptionTime" ServerPreemptionTimeId serverPreemptionTime serverPreemptionTimeChanged_,
      resultContainerProperty c "inputWaitFactor" ServerInputWaitFactorId serverInputWaitFactor serverInputWaitFactorChanged_,
      resultContainerProperty c "processingFactor" ServerProcessingFactorId serverProcessingFactor serverProcessingFactorChanged_,
      resultContainerProperty c "outputWaitFactor" ServerOutputWaitFactorId serverOutputWaitFactor serverOutputWaitFactorChanged_,
      resultContainerProperty c "preemptionFactor" ServerPreemptionFactorId serverPreemptionFactor serverPreemptionFactorChanged_ ] }

-- | Return a source by the specified activity.
activityResultSource :: (MonadDES m,
                         Show s, ResultItemable (ResultValue s))
                        => ResultContainer (Activity m s a b) m
                        -- ^ the activity container
                        -> ResultSource m
activityResultSource c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = ActivityId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = activityResultSummary c,
    resultObjectProperties = [
      resultContainerConstProperty c "initState" ActivityInitStateId activityInitState,
      resultContainerProperty c "state" ActivityStateId activityState activityStateChanged_,
      resultContainerProperty c "totalUtilisationTime" ActivityTotalUtilisationTimeId activityTotalUtilisationTime activityTotalUtilisationTimeChanged_,
      resultContainerProperty c "totalIdleTime" ActivityTotalIdleTimeId activityTotalIdleTime activityTotalIdleTimeChanged_,
      resultContainerProperty c "totalPreemptionTime" ActivityTotalPreemptionTimeId activityTotalPreemptionTime activityTotalPreemptionTimeChanged_,
      resultContainerProperty c "utilisationTime" ActivityUtilisationTimeId activityUtilisationTime activityUtilisationTimeChanged_,
      resultContainerProperty c "idleTime" ActivityIdleTimeId activityIdleTime activityIdleTimeChanged_,
      resultContainerProperty c "preemptionTime" ActivityPreemptionTimeId activityPreemptionTime activityPreemptionTimeChanged_,
      resultContainerProperty c "utilisationFactor" ActivityUtilisationFactorId activityUtilisationFactor activityUtilisationFactorChanged_,
      resultContainerProperty c "idleFactor" ActivityIdleFactorId activityIdleFactor activityIdleFactorChanged_,
      resultContainerProperty c "preemptionFactor" ActivityPreemptionFactorId activityPreemptionFactor activityPreemptionFactorChanged_ ] }

-- | Return a summary by the specified activity.
activityResultSummary :: MonadDES m
                         => ResultContainer (Activity m s a b) m
                         -- ^ the activity container
                         -> ResultSource m
activityResultSummary c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = ActivityId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = activityResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "utilisationTime" ActivityUtilisationTimeId activityUtilisationTime activityUtilisationTimeChanged_,
      resultContainerProperty c "idleTime" ActivityIdleTimeId activityIdleTime activityIdleTimeChanged_,
      resultContainerProperty c "preemptionTime" ActivityPreemptionTimeId activityPreemptionTime activityPreemptionTimeChanged_,
      resultContainerProperty c "utilisationFactor" ActivityUtilisationFactorId activityUtilisationFactor activityUtilisationFactorChanged_,
      resultContainerProperty c "idleFactor" ActivityIdleFactorId activityIdleFactor activityIdleFactorChanged_,
      resultContainerProperty c "preemptionFactor" ActivityPreemptionFactorId activityPreemptionFactor activityPreemptionFactorChanged_ ] }

-- | Return a source by the specified resource.
resourceResultSource :: (MonadDES m,
                         Show s, ResultItemable (ResultValue s))
                        => ResultContainer (Resource m s) m
                        -- ^ the resource container
                        -> ResultSource m
resourceResultSource c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = ResourceId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = resourceResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "queueCount" ResourceQueueCountId resourceQueueCount resourceQueueCountChanged_,
      resultContainerProperty c "queueCountStats" ResourceQueueCountStatsId resourceQueueCountStats resourceQueueCountChanged_,
      resultContainerProperty c "totalWaitTime" ResourceTotalWaitTimeId resourceTotalWaitTime resourceWaitTimeChanged_,
      resultContainerProperty c "waitTime" ResourceWaitTimeId resourceWaitTime resourceWaitTimeChanged_,
      resultContainerProperty c "count" ResourceCountId resourceCount resourceCountChanged_,
      resultContainerProperty c "countStats" ResourceCountStatsId resourceCountStats resourceCountChanged_,
      resultContainerProperty c "utilisationCount" ResourceUtilisationCountId resourceUtilisationCount resourceUtilisationCountChanged_,
      resultContainerProperty c "utilisationCountStats" ResourceUtilisationCountStatsId resourceUtilisationCountStats resourceUtilisationCountChanged_ ] }

-- | Return a summary by the specified resource.
resourceResultSummary :: MonadDES m
                         => ResultContainer (Resource m s) m
                         -- ^ the resource container
                         -> ResultSource m
resourceResultSummary c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = ResourceId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = resourceResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "queueCountStats" ResourceQueueCountStatsId resourceQueueCountStats resourceQueueCountChanged_,
      resultContainerProperty c "waitTime" ResourceWaitTimeId resourceWaitTime resourceWaitTimeChanged_,
      resultContainerProperty c "countStats" ResourceCountStatsId resourceCountStats resourceCountChanged_,
      resultContainerProperty c "utilisationCountStats" ResourceUtilisationCountStatsId resourceUtilisationCountStats resourceUtilisationCountChanged_ ] }

-- | Return a source by the specified resource.
preemptibleResourceResultSource :: PR.MonadResource m
                                   => ResultContainer (PR.Resource m) m
                                   -- ^ the resource container
                                   -> ResultSource m
preemptibleResourceResultSource c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = ResourceId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = preemptibleResourceResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "queueCount" ResourceQueueCountId PR.resourceQueueCount PR.resourceQueueCountChanged_,
      resultContainerProperty c "queueCountStats" ResourceQueueCountStatsId PR.resourceQueueCountStats PR.resourceQueueCountChanged_,
      resultContainerProperty c "totalWaitTime" ResourceTotalWaitTimeId PR.resourceTotalWaitTime PR.resourceWaitTimeChanged_,
      resultContainerProperty c "waitTime" ResourceWaitTimeId PR.resourceWaitTime PR.resourceWaitTimeChanged_,
      resultContainerProperty c "count" ResourceCountId PR.resourceCount PR.resourceCountChanged_,
      resultContainerProperty c "countStats" ResourceCountStatsId PR.resourceCountStats PR.resourceCountChanged_,
      resultContainerProperty c "utilisationCount" ResourceUtilisationCountId PR.resourceUtilisationCount PR.resourceUtilisationCountChanged_,
      resultContainerProperty c "utilisationCountStats" ResourceUtilisationCountStatsId PR.resourceUtilisationCountStats PR.resourceUtilisationCountChanged_ ] }

-- | Return a summary by the specified resource.
preemptibleResourceResultSummary :: PR.MonadResource m
                                    => ResultContainer (PR.Resource m) m
                                    -- ^ the resource container
                                    -> ResultSource m
preemptibleResourceResultSummary c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = ResourceId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = preemptibleResourceResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "queueCountStats" ResourceQueueCountStatsId PR.resourceQueueCountStats PR.resourceQueueCountChanged_,
      resultContainerProperty c "waitTime" ResourceWaitTimeId PR.resourceWaitTime PR.resourceWaitTimeChanged_,
      resultContainerProperty c "countStats" ResourceCountStatsId PR.resourceCountStats PR.resourceCountChanged_,
      resultContainerProperty c "utilisationCountStats" ResourceUtilisationCountStatsId PR.resourceUtilisationCountStats PR.resourceUtilisationCountChanged_ ] }

-- | Return a source by the specified operation.
operationResultSource :: MonadDES m
                         => ResultContainer (Operation m a b) m
                         -- ^ the operation container
                         -> ResultSource m
operationResultSource c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = OperationId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = operationResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "totalUtilisationTime" OperationTotalUtilisationTimeId operationTotalUtilisationTime operationTotalUtilisationTimeChanged_,
      resultContainerProperty c "totalPreemptionTime" OperationTotalPreemptionTimeId operationTotalPreemptionTime operationTotalPreemptionTimeChanged_,
      resultContainerProperty c "utilisationTime" OperationUtilisationTimeId operationUtilisationTime operationUtilisationTimeChanged_,
      resultContainerProperty c "preemptionTime" OperationPreemptionTimeId operationPreemptionTime operationPreemptionTimeChanged_,
      resultContainerProperty c "utilisationFactor" OperationUtilisationFactorId operationUtilisationFactor operationUtilisationFactorChanged_,
      resultContainerProperty c "preemptionFactor" OperationPreemptionFactorId operationPreemptionFactor operationPreemptionFactorChanged_ ] }

-- | Return a summary by the specified operation.
operationResultSummary :: MonadDES m
                          => ResultContainer (Operation m a b) m
                          -- ^ the operation container
                          -> ResultSource m
operationResultSummary c =
  ResultObjectSource $
  ResultObject {
    resultObjectName = resultContainerName c,
    resultObjectId = resultContainerId c,
    resultObjectTypeId = OperationId,
    resultObjectSignal = resultContainerSignal c,
    resultObjectSummary = operationResultSummary c,
    resultObjectProperties = [
      resultContainerProperty c "utilisationTime" OperationUtilisationTimeId operationUtilisationTime operationUtilisationTimeChanged_,
      resultContainerProperty c "preemptionTime" OperationPreemptionTimeId operationPreemptionTime operationPreemptionTimeChanged_,
      resultContainerProperty c "utilisationFactor" OperationUtilisationFactorId operationUtilisationFactor operationUtilisationFactorChanged_,
      resultContainerProperty c "preemptionFactor" OperationPreemptionFactorId operationPreemptionFactor operationPreemptionFactorChanged_ ] }

-- | Return an arbitrary text as a separator source.
textResultSource :: String -> ResultSource m
textResultSource text =
  ResultSeparatorSource $
  ResultSeparator { resultSeparatorText = text }

-- | Return the source of the modeling time.
timeResultSource :: MonadDES m => ResultSource m
timeResultSource = resultSource' "t" ["t"] TimeId [TimeId] time
                         
-- | Make an integer subscript
intSubscript :: Int -> ResultName
intSubscript i = "[" ++ show i ++ "]"

instance {-# OVERLAPPABLE #-} (MonadDES m, ResultItemable (ResultValue a)) => ResultProvider (Parameter m a) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ computeResultValue name names i is m

instance {-# OVERLAPPABLE #-} (MonadDES m, ResultItemable (ResultValue a)) => ResultProvider (Simulation m a) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ computeResultValue name names i is m

instance {-# OVERLAPPABLE #-} (MonadDES m, ResultItemable (ResultValue a)) => ResultProvider (Dynamics m a) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ computeResultValue name names i is m

instance {-# OVERLAPPABLE #-} (MonadDES m, ResultItemable (ResultValue a)) => ResultProvider (Event m a) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ computeResultValue name names i is m

instance {-# OVERLAPPABLE #-} (MonadDES m, ResultItemable (ResultValue a)) => ResultProvider (Ref m a) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ computeResultValue name names i is m

instance {-# OVERLAPPABLE #-} (MonadDES m, ResultItemable (ResultValue a)) => ResultProvider (B.Ref m a) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ computeResultValue name names i is m

instance {-# OVERLAPPABLE #-} (MonadDES m, MonadVar m, ResultItemable (ResultValue a)) => ResultProvider (Var m a) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ computeResultValue name names i is m

instance {-# OVERLAPPABLE #-} (MonadDES m, ResultItemable (ResultValue a)) => ResultProvider (Signalable m a) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (SamplingStats a)))
                             => ResultProvider (Parameter m (SamplingCounter a)) m where

  resultSource' name names i is m =
    samplingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (SamplingStats a)))
                             => ResultProvider (Simulation m (SamplingCounter a)) m where

  resultSource' name names i is m =
    samplingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (SamplingStats a)))
                             => ResultProvider (Dynamics m (SamplingCounter a)) m where

  resultSource' name names i is m =
    samplingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (SamplingStats a)))
                             => ResultProvider (Event m (SamplingCounter a)) m where

  resultSource' name names i is m =
    samplingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (SamplingStats a)))
                             => ResultProvider (Ref m (SamplingCounter a)) m where

  resultSource' name names i is m =
    samplingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (SamplingStats a)))
                             => ResultProvider (B.Ref m (SamplingCounter a)) m where

  resultSource' name names i is m =
    samplingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              MonadVar m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (SamplingStats a)))
                             => ResultProvider (Var m (SamplingCounter a)) m where

  resultSource' name names i is m =
    samplingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (SamplingStats a)))
                             => ResultProvider (Signalable m (SamplingCounter a)) m where

  resultSource' name names i is m =
    samplingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (TimingStats a)))
                             => ResultProvider (Parameter m (TimingCounter a)) m where

  resultSource' name names i is m =
    timingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (TimingStats a)))
                             => ResultProvider (Simulation m (TimingCounter a)) m where

  resultSource' name names i is m =
    timingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (TimingStats a)))
                             => ResultProvider (Dynamics m (TimingCounter a)) m where

  resultSource' name names i is m =
    timingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (TimingStats a)))
                             => ResultProvider (Event m (TimingCounter a)) m where

  resultSource' name names i is m =
    timingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (TimingStats a)))
                             => ResultProvider (Ref m (TimingCounter a)) m where

  resultSource' name names i is m =
    timingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (TimingStats a)))
                             => ResultProvider (B.Ref m (TimingCounter a)) m where

  resultSource' name names i is m =
    timingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              MonadVar m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (TimingStats a)))
                             => ResultProvider (Var m (TimingCounter a)) m where

  resultSource' name names i is m =
    timingCounterResultSource $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m,
                              ResultItemable (ResultValue a),
                              ResultItemable (ResultValue (TimingStats a)))
                             => ResultProvider (Signalable m (TimingCounter a)) m where

  resultSource' name names i is m =
    timingCounterResultSource $ computeResultValue name names i is m

instance ResultProvider p m => ResultProvider [p] m where

  resultSource' name names i is m =
    resultSource' name names i is $ ResultListWithSubscript m subscript where
      subscript = map snd $ zip m $ map intSubscript [0..]

instance (Show i, Ix i, ResultProvider p m) => ResultProvider (A.Array i p) m where

  resultSource' name names i is m =
    resultSource' name names i is $ ResultListWithSubscript items subscript where
      items = A.elems m
      subscript = map (\i -> "[" ++ show i ++ "]") (A.indices m)

instance ResultProvider p m => ResultProvider (V.Vector p) m where
  
  resultSource' name names i is m =
    resultSource' name names i is $ ResultVectorWithSubscript m subscript where
      subscript = V.imap (\i x -> intSubscript i) m

-- | Represents a list with the specified subscript.
data ResultListWithSubscript p =
  ResultListWithSubscript [p] [String]

-- | Represents an array with the specified subscript.
data ResultArrayWithSubscript i p =
  ResultArrayWithSubscript (A.Array i p) (A.Array i String)

-- | Represents a vector with the specified subscript.
data ResultVectorWithSubscript p =
  ResultVectorWithSubscript (V.Vector p) (V.Vector String)

instance ResultProvider p m => ResultProvider (ResultListWithSubscript p) m where

  resultSource' name names i is (ResultListWithSubscript xs ys) =
    ResultVectorSource $
    memoResultVectorSignal $
    memoResultVectorSummary $
    ResultVector { resultVectorName = name,
                   resultVectorId = i,
                   resultVectorItems = axs,
                   resultVectorSubscript = ays,
                   resultVectorSignal = undefined,
                   resultVectorSummary = undefined }
    where
      bnds   = (0, length xs - 1)
      axs    = A.listArray bnds items
      ays    = A.listArray bnds ys
      items  =
        flip map (zip ys xs) $ \(y, x) ->
        let name'  = name ++ y
            names' = names ++ [y]
            i'  = VectorItemId y
            is' = is ++ [i']
        in resultSource' name' names' i' is' x
      items' = map resultSourceSummary items

instance (Show i, Ix i, ResultProvider p m) => ResultProvider (ResultArrayWithSubscript i p) m where

  resultSource' name names i is (ResultArrayWithSubscript xs ys) =
    resultSource' name names i is $ ResultListWithSubscript items subscript where
      items = A.elems xs
      subscript = A.elems ys

instance ResultProvider p m => ResultProvider (ResultVectorWithSubscript p) m where

  resultSource' name names i is (ResultVectorWithSubscript xs ys) =
    ResultVectorSource $
    memoResultVectorSignal $
    memoResultVectorSummary $
    ResultVector { resultVectorName = name,
                   resultVectorId = i,
                   resultVectorItems = axs,
                   resultVectorSubscript = ays,
                   resultVectorSignal = undefined,
                   resultVectorSummary = undefined }
    where
      bnds   = (0, V.length xs - 1)
      axs    = A.listArray bnds (V.toList items)
      ays    = A.listArray bnds (V.toList ys)
      items =
        V.generate (V.length xs) $ \i ->
        let x = xs V.! i
            y = ys V.! i
            name'  = name ++ y
            names' = names ++ [y]
            i'  = VectorItemId y
            is' = is ++ [i']
        in resultSource' name' names' i' is' x
      items' = V.map resultSourceSummary items

instance {-# OVERLAPPING #-} (Ix i, Show i, MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Parameter m (A.Array i e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue A.elems $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (Ix i, Show i, MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Simulation m (A.Array i e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue A.elems $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (Ix i, Show i, MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Dynamics m (A.Array i e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue A.elems $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (Ix i, Show i, MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Event m (A.Array i e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue A.elems $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (Ix i, Show i, MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Ref m (A.Array i e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue A.elems $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (Ix i, Show i, MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (B.Ref m (A.Array i e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue A.elems $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (Ix i, Show i, MonadDES m, MonadVar m, ResultItemable (ResultValue [e])) => ResultProvider (Var m (A.Array i e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue A.elems $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (Ix i, Show i, MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Signalable m (A.Array i e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue A.elems $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Parameter m (V.Vector e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue V.toList $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Simulation m (V.Vector e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue V.toList $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Dynamics m (V.Vector e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue V.toList $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Event m (V.Vector e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue V.toList $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Ref m (V.Vector e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue V.toList $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (B.Ref m (V.Vector e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue V.toList $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m, MonadVar m, ResultItemable (ResultValue [e])) => ResultProvider (Var m (V.Vector e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue V.toList $ computeResultValue name names i is m

instance {-# OVERLAPPING #-} (MonadDES m, ResultItemable (ResultValue [e])) => ResultProvider (Signalable m (V.Vector e)) m where

  resultSource' name names i is m =
    ResultItemSource $ ResultItem $ mapResultValue V.toList $ computeResultValue name names i is m

instance (MonadDES m,
          Show si, Show sm, Show so,
          ResultItemable (ResultValue si),
          ResultItemable (ResultValue sm),
          ResultItemable (ResultValue so))
         => ResultProvider (Q.Queue m si sm so a) m where

  resultSource' name names i is m =
    queueResultSource $ ResultContainer name names i is m (ResultSignal $ Q.queueChanged_ m)

instance (MonadDES m,
          Show sm, Show so,
          ResultItemable (ResultValue sm),
          ResultItemable (ResultValue so))
         => ResultProvider (IQ.Queue m sm so a) m where

  resultSource' name names i is m =
    infiniteQueueResultSource $ ResultContainer name names i is m (ResultSignal $ IQ.queueChanged_ m)

instance MonadDES m => ResultProvider (ArrivalTimer m) m where

  resultSource' name names i is m =
    arrivalTimerResultSource $ ResultContainer name names i is m (ResultSignal $ arrivalProcessingTimeChanged_ m)

instance (MonadDES m, Show s, ResultItemable (ResultValue s)) => ResultProvider (Server m s a b) m where

  resultSource' name names i is m =
    serverResultSource $ ResultContainer name names i is m (ResultSignal $ serverChanged_ m)

instance (MonadDES m, Show s, ResultItemable (ResultValue s)) => ResultProvider (Activity m s a b) m where

  resultSource' name names i is m =
    activityResultSource $ ResultContainer name names i is m (ResultSignal $ activityChanged_ m)

instance (MonadDES m, Show s, ResultItemable (ResultValue s)) => ResultProvider (Resource m s) m where

  resultSource' name names i is m =
    resourceResultSource $ ResultContainer name names i is m (ResultSignal $ resourceChanged_ m)

instance PR.MonadResource m => ResultProvider (PR.Resource m) m where

  resultSource' name names i is m =
    preemptibleResourceResultSource $ ResultContainer name names i is m (ResultSignal $ PR.resourceChanged_ m)

instance MonadDES m => ResultProvider (Operation m a b) m where

  resultSource' name names i is m =
    operationResultSource $ ResultContainer name names i is m (ResultSignal $ operationChanged_ m)
