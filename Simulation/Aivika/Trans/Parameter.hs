-- |
-- Module     : Simulation.Aivika.Trans.Parameter
-- Copyright  : Copyright (c) 2009-2017, David Sorokin <david.sorokin@gmail.com>
-- License    : BSD3
-- Maintainer : David Sorokin <david.sorokin@gmail.com>
-- Stability  : experimental
-- Tested with: GHC 8.0.1
--
-- The module defines the 'Parameter' monad transformer that allows representing the model
-- parameters. For example, they can be used when running the Monte-Carlo simulation.
--
-- In general, this monad tranformer is very useful for representing a computation which is external
-- relative to the model itself.
-- 
module Simulation.Aivika.Trans.Parameter
       (-- * Parameter
        Parameter,
        ParameterLift(..),
        runParameter,
        runParameters,
        -- * Error Handling
        catchParameter,
        finallyParameter,
        throwParameter,
        -- * Predefined Parameters
        simulationIndex,
        simulationCount,
        simulationSpecs,
        generatorParameter,
        starttime,
        stoptime,
        dt,
        -- * Memoization
        memoParameter,
        -- * Utilities
        tableParameter) where

import Simulation.Aivika.Trans.Internal.Parameter
