#ifndef CROC_INTERNAL_GC_HPP
#define CROC_INTERNAL_GC_HPP

#include "croc/types/base.hpp"

namespace croc
{
	void runFinalizers(Thread* t);
}

#endif