module test;

import tango.io.Stdout;
debug import tango.stdc.stdarg; // To make tango-user-base-debug.lib link correctly

import minid.api;

void main()
{
	scope(exit) Stdout.flush;

	MDVM vm;
	auto t = openVM(&vm);
	loadStdlibs(t);

	try
	{
// 		importModule(t, "samples.simple");
// 		pushNull(t);
// 		pushGlobal(t, "runMain");
// 		swap(t, -3);
// 		rawCall(t, -3, 0);

		lookup(t, "modules.customLoaders");

		foreach(word v; foreachLoop(t, 1))
		{
			pushToString(t, v);
			Stdout.formatln("{}", getString(t, -1));
			pop(t);
		}
	}
	catch(MDException e)
	{
		auto ex = catchException(t);
		Stdout.formatln("Error: {}", e);
	}
	catch(Exception e)
	{
		Stdout.formatln("Bad error ({}, {}): {}", e.file, e.line, e);
		return;
	}

	Stdout.newline.format("MiniD using {} bytes before GC, ", bytesAllocated(&vm)).flush;
	gc(t);
	Stdout.formatln("{} bytes after.", bytesAllocated(&vm)).flush;

	closeVM(&vm);
}