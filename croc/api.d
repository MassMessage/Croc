/******************************************************************************
This should be the module you import to use Croc. This module publicly
imports the following modules: croc.base_alloc, croc.ex croc.interpreter,
croc.stackmanip, croc.types, croc.utils and croc.vm.

License:
Copyright (c) 2008 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.api;

import tango.core.Exception;
import tango.stdc.stdlib;

public
{
	import croc.api_interpreter;
	import croc.api_stack;
	import croc.base_alloc;
	import croc.ex;
	import croc.types;
	import croc.utils;
	import croc.vm;
}

import croc.compiler;
import croc.stdlib_array;
import croc.stdlib_ascii;
import croc.stdlib_base;
import croc.stdlib_compiler;
import croc.stdlib_console;
import croc.stdlib_debug;
import croc.stdlib_docs;
import croc.stdlib_env;
import croc.stdlib_exceptions;
import croc.stdlib_file;
import croc.stdlib_gc;
import croc.stdlib_hash;
import croc.stdlib_json;
import croc.stdlib_math;
import croc.stdlib_memblock;
import croc.stdlib_modules;
import croc.stdlib_object;
import croc.stdlib_os;
import croc.stdlib_path;
// import croc.stdlib_serialization;
import croc.stdlib_stream;
import croc.stdlib_string;
import croc.stdlib_text;
import croc.stdlib_thread;
import croc.stdlib_time;

import croc.addons.pcre;
import croc.addons.sdl;
import croc.addons.gl;
import croc.addons.net;
import croc.addons.devil;

version(CrocAllAddons)
{
	version = CrocPcreAddon;
	version = CrocSdlAddon;
	version = CrocGlAddon;
	version = CrocNetAddon;
	version = CrocDevilAddon;
}

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

/**
The default memory-allocation function, which uses the C allocator.
*/
void* DefaultMemFunc(void* ctx, void* p, uword oldSize, uword newSize)
{
	if(newSize == 0)
	{
		tango.stdc.stdlib.free(p);
		return null;
	}
	else
	{
		auto ret = tango.stdc.stdlib.realloc(p, newSize);

		if(ret is null)
			onOutOfMemoryError();

		return ret;
	}
}

/**
Initialize a VM instance. This is independent from all other VM instances. It performs its
own garbage collection, and as far as I know, multiple OS threads can each have their own
VM and manipulate them at the same time without consequence. (The library has not, however,
been designed with multithreading in mind, so you will have to synchronize access to a single
VM from multiple threads.)

This call also allocates an instance of tango.text.convert.Layout on the D heap, so that the
library can perform formatting without allocating memory later.

Params:
	vm = The VM object to initialize. $(B This object must have been allocated somewhere in D
		memory) (either on the stack or with 'new'). If it's not in D's memory, you must inform
		the D GC of its existence, or else D will blindly collect objects that the Croc VM
		references.
	memFunc = The memory allocation function to use to allocate this VM. The VM's allocation
		function will be set to this after creation. Defaults to DefaultMemFunc, which uses
		the C allocator.
	ctx = An opaque context pointer that will be passed to the memory function at each call.
		The Croc library does not do anything with this pointer other than store it. Note that
		since it is stored in the VM structure, it can safely point into D heap memory.

Returns:
	The newly-opened VM's main thread.
*/
CrocThread* openVM(CrocVM* vm, MemFunc memFunc = &DefaultMemFunc, void* ctx = null)
{
	openVMImpl(vm, memFunc, ctx);
	auto t = mainThread(vm);

	version(CrocBuiltinDocs)
		Compiler.setDefaultFlags(t, Compiler.AllDocs);

	// Core libs
	initModulesLib(t);
	initExceptionsLib(t);
	initGCLib(t);

	// Safe libs
	initBaseLib(t);
	initStringLib(t);
	initDocsLib(t); // implicitly depends on the stringlib because of how ex_doccomments is implemented

	// Go back and document the libs that we loaded before the doc lib (this is easier than partly-loading the doclib and fixing things later.. OR IS IT)
	version(CrocBuiltinDocs)
	{
		docModulesLib(t);
		docExceptionsLib(t);
		docGCLib(t);
		docBaseLib(t);
		docStringLib(t);
	}

	// Finish up the safe libs.
	HashLib.init(t);
	MathLib.init(t);
	initObjectLib(t);
	initMemblockLib(t);
	initTextLib(t); // depends on memblock
	initStreamLib(t); // depends on math, object, text
	initArrayLib(t);
	initAsciiLib(t);
	CompilerLib.init(t);
	initConsoleLib(t); // depends on stream
	initEnvLib(t);
	JSONLib.init(t); // depends on stream
	initPathLib(t);
	// SerializationLib.init(t); // depends on stream
	ThreadLib.init(t);
	TimeLib.init(t);

	version(CrocBuiltinDocs)
		Compiler.setDefaultFlags(t, Compiler.All);

	// Done, turn the GC back on and clear out any garbage we made.
	enableGC(vm);
	gc(t);

	return t;
}

/**
Closes a VM object and deallocates all memory associated with it. This also runs finalizers on all
remaining finalizable objects. Finalization is guaranteed so that long-running processes can create
and destroy VMs without having to worry about Croc code never releasing system resources like file
handles. Of course, if there is an error in a finalizer, the finalization process will be halted and
the VM will be in an unclosable state. This is why making finalizers not fail is important.

Params:
	vm = The VM to free. After all memory has been freed, the memory at this pointer will be initialized
		to an "empty" or "dead" VM which can then be passed into openVM.
*/
void closeVM(CrocVM* vm)
{
	closeVMImpl(vm);
}

/**
This enum lists the unsafe standard libraries to be used with loadUnsafeLibs. You can choose which
libraries you want to load by bitwise-ORing together multiple flags.
*/
enum CrocUnsafeLib
{
	None =  0, /// No unsafe libraries.
	File =  1, /// File system manipulation and file access.
	OS =    2, /// _OS-specific functionality.
	Debug = 4, /// Debugging introspection and hooks.

	/** _All available unsafe libraries except the debug library. */
	All = File | OS,

	/** All available unsafe libraries including the debug library. */
	ReallyAll = All | Debug
}

/**
Load the unsafe standard libraries into the given thread's VM.

Params:
	libs = An ORing together of any unsafe standard libraries you want to load (see the CrocUnsafeLib enum).
		Defaults to CrocUnsafeLib.All.
*/
void loadUnsafeLibs(CrocThread* t, uint libs = CrocUnsafeLib.All)
{
	if(libs & CrocUnsafeLib.File)  FileLib.init(t);
	if(libs & CrocUnsafeLib.OS)    OSLib.init(t);
	if(libs & CrocUnsafeLib.Debug) DebugLib.init(t);
}

/**
This enum lists the addon libraries to be used with loadAddons. You can choose which addons you want to load by bitwise-
ORing together multiple flags. See loadAddons for more info.
*/
enum CrocAddons
{
	None =  0,  /// No addon libraries
	Pcre =  1,  /// Perl-compatible regexes
	Sdl =   2,  /// SDL
	Devil = 4,  /// DevIL (image library)
	Gl =    8,  /// OpenGL
	Net =   16, /// TCP/IP Sockets

	/** All the safe addons (PCRE and SDL). */
	Safe = Pcre | Sdl,

	/** All the unsafe addons (DevIL, OpenGL, and networking). */
	Unsafe = Devil | Gl | Net,

	/** All available addons. */
	All = Safe | Unsafe
}

/**
Load the addon libraries into the given thread's VM.

Note that even though you are free to specify any addon library in the libs parameter, you must actually enable the
addons that you want with the appropriate conditional compilation flags. If you don't, you'll get a runtime error when
attempting to load an addon that wasn't compiled in.

Params:
	libs = An ORing together of any addon libraries you want to load (see the CrocAddons enum).
*/
void loadAddons(CrocThread* t, uint libs)
{
	if(libs & CrocAddons.Pcre)  PcreLib.init(t);
	if(libs & CrocAddons.Sdl)   initSdlLib(t);
	if(libs & CrocAddons.Devil) DevilLib.init(t);
	if(libs & CrocAddons.Gl)    GlLib.init(t);
	if(libs & CrocAddons.Net)   initNetLib(t);
}

/**
Loads all available addon libraries into the given thread's VM.

This is a shortcut for a common case where which addons you want to load is entirely specified by the conditional
compilation flags. For instance, if you use the CrocSdlAddon and CrocGlAddon versions, this function will load those
two addons and nothing else.

Params:
	exclude = An ORing together of any addon libraries you $(B don't) want to load (see the CrocAddons enum). Defaults
		to CrocAddons.None, in which case none will be excluded.
*/
void loadAvailableAddons(CrocThread* t, uint exclude = CrocAddons.None)
{
	version(CrocPcreAddon)  if(!(exclude & CrocAddons.Pcre))  PcreLib.init(t);
	version(CrocSdlAddon)   if(!(exclude & CrocAddons.Sdl))   initSdlLib(t);
	version(CrocDevilAddon) if(!(exclude & CrocAddons.Devil)) DevilLib.init(t);
	version(CrocGlAddon)    if(!(exclude & CrocAddons.Gl))    GlLib.init(t);
	version(CrocNetAddon)   if(!(exclude & CrocAddons.Net))   initNetLib(t);
}