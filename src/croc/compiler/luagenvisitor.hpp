#ifndef CROC_COMPILER_LUAGENVISITOR_HPP
#define CROC_COMPILER_LUAGENVISITOR_HPP

#include "croc/compiler/astvisitor.hpp"
#include "croc/compiler/types.hpp"

class LuaGenVisitor : public IdentityVisitor
{
private:
	uword mDummyNameCounter = 0;

public:
	LuaGenVisitor(Compiler& c) :
		IdentityVisitor(c),
		mDummyNameCounter(0)
	{}

	using AstVisitor::visit;

	bool isTopLevel() { return true; }
	Identifier* genDummyVar(CompileLoc loc, const char* fmt);

	virtual FuncDef* visit(FuncDef* d) override;
	virtual Statement* visit(ImportStmt* s) override;
	virtual ScopeStmt* visit(ScopeStmt* s) override;
	virtual ExpressionStmt* visit(ExpressionStmt* s) override;
	virtual VarDecl* visit(VarDecl* d) override;
	virtual Decorator* visit(Decorator* d) override;
	virtual FuncDecl* visit(FuncDecl* d) override;
	virtual Statement* visit(BlockStmt* s) override;
	virtual Statement* visit(IfStmt* s) override;
	virtual Statement* visit(WhileStmt* s) override;
	virtual Statement* visit(DoWhileStmt* s) override;
	virtual Statement* visit(ForStmt* s) override;
	virtual Statement* visit(ForNumStmt* s) override;
	virtual ForeachStmt* visit(ForeachStmt* s) override;
	virtual ContinueStmt* visit(ContinueStmt* s) override;
	virtual BreakStmt* visit(BreakStmt* s) override;
	virtual ReturnStmt* visit(ReturnStmt* s) override;
	virtual AssignStmt* visit(AssignStmt* s) override;
	virtual AddAssignStmt* visit(AddAssignStmt* s) override;
	virtual SubAssignStmt* visit(SubAssignStmt* s) override;
	virtual MulAssignStmt* visit(MulAssignStmt* s) override;
	virtual DivAssignStmt* visit(DivAssignStmt* s) override;
	virtual ModAssignStmt* visit(ModAssignStmt* s) override;
	virtual ShlAssignStmt* visit(ShlAssignStmt* s) override;
	virtual ShrAssignStmt* visit(ShrAssignStmt* s) override;
	virtual UShrAssignStmt* visit(UShrAssignStmt* s) override;
	virtual XorAssignStmt* visit(XorAssignStmt* s) override;
	virtual OrAssignStmt* visit(OrAssignStmt* s) override;
	virtual AndAssignStmt* visit(AndAssignStmt* s) override;
	virtual Statement* visit(CondAssignStmt* s) override;
	virtual CatAssignStmt* visit(CatAssignStmt* s) override;
	virtual IncStmt* visit(IncStmt* s) override;
	virtual DecStmt* visit(DecStmt* s) override;
	virtual Expression* visit(CondExp* e) override;
	virtual Expression* visit(OrOrExp* e) override;
	virtual Expression* visit(AndAndExp* e) override;
	virtual Expression* visit(OrExp* e) override;
	virtual Expression* visit(XorExp* e) override;
	virtual Expression* visit(AndExp* e) override;
	virtual Expression* visit(EqualExp* e) override;
	virtual Expression* visit(NotEqualExp* e) override;
	virtual Expression* visit(IsExp* e) override;
	virtual Expression* visit(NotIsExp* e) override;
	virtual Expression* visit(LTExp* e) override;
	virtual Expression* visit(LEExp* e) override;
	virtual Expression* visit(GTExp* e) override;
	virtual Expression* visit(GEExp* e) override;
	virtual Expression* visit(Cmp3Exp* e) override;
	virtual Expression* visit(ShlExp* e) override;
	virtual Expression* visit(ShrExp* e) override;
	virtual Expression* visit(UShrExp* e) override;
	virtual Expression* visit(AddExp* e) override;
	virtual Expression* visit(SubExp* e) override;
	virtual Expression* visit(CatExp* e) override;
	virtual Expression* visit(MulExp* e) override;
	virtual Expression* visit(DivExp* e) override;
	virtual Expression* visit(ModExp* e) override;
	virtual Expression* visit(NegExp* e) override;
	virtual Expression* visit(NotExp* e) override;
	virtual Expression* visit(ComExp* e) override;
	virtual Expression* visit(LenExp* e) override;
	virtual Expression* visit(DotExp* e) override;
	virtual Expression* visit(MethodCallExp* e) override;
	virtual Expression* visit(CallExp* e) override;
	virtual Expression* visit(IndexExp* e) override;
	virtual Expression* visit(VargIndexExp* e) override;
	virtual FuncLiteralExp* visit(FuncLiteralExp* e) override;
	virtual Expression* visit(ParenExp* e) override;
	virtual TableCtorExp* visit(TableCtorExp* e) override;
	virtual ArrayCtorExp* visit(ArrayCtorExp* e) override;
	virtual YieldExp* visit(YieldExp* e) override;
};

#endif