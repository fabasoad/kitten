{-# LANGUAGE OverloadedStrings #-}

module Kitten.Resolve
  ( resolve
  ) where

import Control.Applicative

import Kitten.Def
import Kitten.Error
import Kitten.Fragment
import Kitten.Location
import Kitten.Name
import Kitten.Resolve.Monad
import Kitten.Resolved
import Kitten.Term (Term)
import Kitten.Util.Void

import qualified Kitten.Resolved as Resolved
import qualified Kitten.Term as Term

resolve
  :: Fragment Resolved.Value Void
  -> Fragment Term.Value Term
  -> Either [CompileError] (Fragment Value Resolved)
resolve prelude (Fragment defs terms)
  = evalResolution emptyEnv
  $ guardLiftM2 Fragment
    (resolveDefs defs)
    (guardMapM resolveTerm terms)
  where emptyEnv = Env (fragmentDefs prelude) defs []

resolveDefs :: [Def Term.Value] -> Resolution [Def Value]
resolveDefs = guardMapM resolveDef
  where
  resolveDef :: Def Term.Value -> Resolution (Def Value)
  resolveDef def = do
    defTerm' <- resolveValue (defTerm def)
    return def { defTerm = defTerm' }

resolveTerm :: Term -> Resolution Resolved
resolveTerm unresolved = case unresolved of
  Term.Call name loc -> resolveName name loc
  Term.Push value loc -> Push <$> resolveValue value <*> pure loc
  Term.Builtin name loc -> return $ Builtin name loc
  Term.Compose terms -> Compose
    <$> guardMapM resolveTerm terms
  Term.Lambda name term loc -> withLocal name
    $ Scoped
    <$> resolveTerm term
    <*> pure loc
  Term.If true false loc -> If
    <$> resolveTerm true
    <*> resolveTerm false
    <*> pure loc
  Term.PairTerm as bs loc -> PairTerm
    <$> resolveTerm as
    <*> resolveTerm bs
    <*> pure loc
  Term.VectorTerm items loc -> VectorTerm
    <$> guardMapM resolveTerm items
    <*> pure loc

resolveValue :: Term.Value -> Resolution Value
resolveValue unresolved = case unresolved of
  Term.Bool value _ -> return $ Bool value
  Term.Char value _ -> return $ Char value
  Term.Float value _ -> return $ Float value
  Term.Function term _ -> Function
    <$> (Compose <$> guardMapM resolveTerm term)
  Term.Int value _ -> return $ Int value
  Term.Pair a b _ -> do
    a' <- resolveValue a
    b' <- resolveValue b
    return $ Pair a' b'
  Term.Unit _ -> return Unit
  Term.Vector values _ -> Vector <$> resolveVector values
  where
  resolveVector = guardMapM resolveValue

resolveName
  :: String
  -> Location
  -> Resolution Resolved
resolveName name loc = do
  mLocalIndex <- getsEnv $ localIndex name
  case mLocalIndex of
    Just index -> return $ Push (Local $ Name index) loc
    Nothing -> do
      indices <- getsEnv $ defIndices name
      index <- case indices of
        [index] -> return index
        [] -> compileError . CompileError loc $ unwords
          ["undefined word:", name]
        _ -> compileError . CompileError loc $ unwords
          ["ambiguous word:", name]
      return $ Call (Name index) loc
