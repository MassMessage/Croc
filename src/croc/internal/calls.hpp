#ifndef CROC_INTERNAL_CALLS_HPP
#define CROC_INTERNAL_CALLS_HPP

#include "croc/base/metamethods.hpp"
#include "croc/types.hpp"

namespace croc
{
	Namespace* getEnv(Thread* t, uword depth = 0);
	Value lookupMethod(Thread* t, Value v, String* name);
	Value getInstanceMethod(Thread* t, Instance* inst, String* name);
	Value getGlobalMetamethod(Thread* t, CrocType type, String* name);
	Function* getMM(Thread* t, Value obj, Metamethod method);
	Namespace* getMetatable(Thread* t, CrocType type);
	void closeUpvals(Thread* t, AbsStack index);
	Upval* findUpval(Thread* t, uword num);
	ActRecord* pushAR(Thread* t);
	// void popAR(Thread* t);
	void popARTo(Thread* t, uword removeTo);
	void callEpilogue(Thread* t);
	void saveResults(Thread* t, Thread* from, AbsStack first, uword num);
	DArray<Value> loadResults(Thread* t);
}

#endif