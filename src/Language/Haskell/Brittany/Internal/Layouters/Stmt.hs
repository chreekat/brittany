{-# LANGUAGE DataKinds #-}

module Language.Haskell.Brittany.Internal.Layouters.Stmt
  ( layoutStmt
  )
where



#include "prelude.inc"

import           Language.Haskell.Brittany.Internal.Types
import           Language.Haskell.Brittany.Internal.LayouterBasics
import           Language.Haskell.Brittany.Internal.Config.Types

import           GHC ( runGhc, GenLocated(L), moduleNameString )
import           HsSyn
import           Name
import qualified FastString
import           BasicTypes

import           Language.Haskell.Brittany.Internal.Layouters.Pattern
import           Language.Haskell.Brittany.Internal.Layouters.Decl
import {-# SOURCE #-} Language.Haskell.Brittany.Internal.Layouters.Expr



layoutStmt :: ToBriDoc' (StmtLR GhcPs GhcPs (LHsExpr GhcPs))
layoutStmt lstmt@(L _ stmt) = do
  indentPolicy <- mAsk <&> _conf_layout .> _lconfig_indentPolicy .> confUnpack
  docWrapNode lstmt $ case stmt of
    LastStmt body False _ -> do
      layoutExpr body
    BindStmt lPat expr _ _ _ -> do
      patDoc <- fmap return $ colsWrapPat =<< layoutPat lPat
      expDoc <- docSharedWrapper layoutExpr expr
      docAlt
        [ docCols
          ColBindStmt
          [ appSep patDoc
          , docSeq [appSep $ docLit $ Text.pack "<-", docForceParSpacing expDoc]
          ]
        , docCols
          ColBindStmt
          [ appSep patDoc
          , docAddBaseY BrIndentRegular
            $ docPar (docLit $ Text.pack "<-") (expDoc)
          ]
        ]
    LetStmt binds -> layoutLocalBinds binds >>= \case
      Nothing        -> docLit $ Text.pack "let" -- i just tested
                                -- it, and it is
                                -- indeed allowed.
                                -- heh.
      Just []        -> docLit $ Text.pack "let" -- this probably never happens
      Just [bindDoc] -> docAlt
        [ -- let bind = expr
          docCols
          ColDoLet
          [ appSep $ docLit $ Text.pack "let"
          , ( if indentPolicy == IndentPolicyLeft
              then docForceSingleline
              else docSetBaseAndIndent
            )
            $ return bindDoc
          ]
        , -- let
          --   bind = expr
          docAddBaseY BrIndentRegular $ docPar
          (docLit $ Text.pack "let")
          (docSetBaseAndIndent $ return bindDoc)
        ]
      Just bindDocs -> runFilteredAlternative $ do
        -- let aaa = expra
        --     bbb = exprb
        --     ccc = exprc
        addAlternativeCond (indentPolicy /= IndentPolicyLeft)
          $ docSeq
          [ appSep $ docLit $ Text.pack "let"
          , docSetBaseAndIndent $ docLines $ return <$> bindDocs
          ]
        -- let
        --   aaa = expra
        --   bbb = exprb
        --   ccc = exprc
        addAlternative $
          docAddBaseY BrIndentRegular $ docPar
            (docLit $ Text.pack "let")
            (docSetBaseAndIndent $ docLines $ return <$> bindDocs)
    RecStmt stmts _ _ _ _ _ _ _ _ _ -> runFilteredAlternative $ do
      -- rec stmt1
      --     stmt2
      --     stmt3
      addAlternativeCond (indentPolicy /= IndentPolicyLeft)
        $ docSeq
        [ docLit (Text.pack "rec")
        , docSeparator
        , docSetBaseAndIndent $ docLines $ layoutStmt <$> stmts
        ]
      -- rec
      --   stmt1
      --   stmt2
      --   stmt3
      addAlternative
        $ docAddBaseY BrIndentRegular
        $ docPar (docLit (Text.pack "rec")) (docLines $ layoutStmt <$> stmts)
    BodyStmt expr _ _ _ -> do
      expDoc <- docSharedWrapper layoutExpr expr
      docAddBaseY BrIndentRegular $ expDoc
    _ -> briDocByExactInlineOnly "some unknown statement" lstmt
