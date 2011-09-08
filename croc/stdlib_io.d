/******************************************************************************
This module contains the 'io' standard library.

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

module croc.stdlib_io;

import Path = tango.io.Path;
import tango.io.device.File;
import tango.io.stream.Buffered;
import tango.io.UnicodeFile;
import tango.sys.Environment;
import tango.time.WallClock;
import tango.time.Time;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.stdlib_stream;
import croc.stdlib_time;
import croc.types;

struct IOLib
{
static:
	public void init(CrocThread* t)
	{
		makeModule(t, "io", function uword(CrocThread* t)
		{
			importModuleNoNS(t, "stream");

			lookup(t, "stream.stdin");
			newGlobal(t, "stdin");

			lookup(t, "stream.stdout");
			newGlobal(t, "stdout");

			lookup(t, "stream.stderr");
			newGlobal(t, "stderr");

			newFunction(t, 1, &inFile,                "inFile");        newGlobal(t, "inFile");
			newFunction(t, 2, &outFile,               "outFile");       newGlobal(t, "outFile");
			newFunction(t, 2, &inoutFile,             "inoutFile");     newGlobal(t, "inoutFile");
			newFunction(t, 2, &rename,                "rename");        newGlobal(t, "rename");
			newFunction(t, 1, &remove,                "remove");        newGlobal(t, "remove");
			newFunction(t, 2, &copy,                  "copy");          newGlobal(t, "copy");
			newFunction(t, 1, &size,                  "size");          newGlobal(t, "size");
			newFunction(t, 1, &exists,                "exists");        newGlobal(t, "exists");
			newFunction(t, 1, &isFile,                "isFile");        newGlobal(t, "isFile");
			newFunction(t, 1, &isDir,                 "isDir");         newGlobal(t, "isDir");
			newFunction(t, 1, &isReadOnly,            "isReadOnly");    newGlobal(t, "isReadOnly");
			newFunction(t, 2, &fileTime!("modified"), "modified");      newGlobal(t, "modified");
			newFunction(t, 2, &fileTime!("created"),  "created");       newGlobal(t, "created");
			newFunction(t, 2, &fileTime!("accessed"), "accessed");      newGlobal(t, "accessed");
			newFunction(t, 0, &currentDir,            "currentDir");    newGlobal(t, "currentDir");
			newFunction(t, 1, &parentDir,             "parentDir");     newGlobal(t, "parentDir");
			newFunction(t, 1, &changeDir,             "changeDir");     newGlobal(t, "changeDir");
			newFunction(t, 1, &makeDir,               "makeDir");       newGlobal(t, "makeDir");
			newFunction(t, 1, &makeDirChain,          "makeDirChain");  newGlobal(t, "makeDirChain");
			newFunction(t, 1, &removeDir,             "removeDir");     newGlobal(t, "removeDir");
			newFunction(t, 3, &listFiles,             "listFiles");     newGlobal(t, "listFiles");
			newFunction(t, 3, &listDirs,              "listDirs");      newGlobal(t, "listDirs");
			newFunction(t, 2, &readFile,              "readFile");      newGlobal(t, "readFile");
			newFunction(t, 2, &writeFile,             "writeFile");     newGlobal(t, "writeFile");
			newFunction(t, 1, &readMemblock,          "readMemblock");  newGlobal(t, "readMemblock");
			newFunction(t, 2, &writeMemblock,         "writeMemblock"); newGlobal(t, "writeMemblock");
			newFunction(t,    &join,                  "join");          newGlobal(t, "join");
			newFunction(t, 1, &dirName,               "dirName");       newGlobal(t, "dirName");
			newFunction(t, 1, &name,                  "name");          newGlobal(t, "name");
			newFunction(t, 1, &extension,             "extension");     newGlobal(t, "extension");
			newFunction(t, 1, &fileName,              "fileName");      newGlobal(t, "fileName");

				newFunction(t, &linesIterator, "linesIterator");
			newFunction(t, 1, &lines, "lines", 1);        newGlobal(t, "lines");

			return 0;
		});

		importModuleNoNS(t, "io");
	}

	uword inFile(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto f = safeCode(t, new BufferedInput(new File(name, File.ReadExisting)));

		lookupCT!("stream.InStream")(t);
		pushNull(t);
		pushNativeObj(t, f);
		rawCall(t, -3, 1);

		return 1;
	}

	uword outFile(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto mode = optCharParam(t, 2, 'c');

		File.Style style;

		switch(mode)
		{
			case 'e': style = File.WriteExisting;  break;
			case 'a': style = File.WriteAppending; break;
			case 'c': style = File.WriteCreate;    break;
			default:
				throwStdException(t, "ValueException", "Unknown open mode '{}'", mode);
		}

		auto f = safeCode(t, new BufferedOutput(new File(name, style)));

		lookupCT!("stream.OutStream")(t);
		pushNull(t);
		pushNativeObj(t, f);
		rawCall(t, -3, 1);

		return 1;
	}

	uword inoutFile(CrocThread* t)
	{
		static const File.Style ReadWriteAppending = { File.Access.ReadWrite, File.Open.Append };

		auto name = checkStringParam(t, 1);
		auto mode = optCharParam(t, 2, 'e');

		File.Style style;

		switch(mode)
		{
			case 'e': style = File.ReadWriteExisting; break;
			case 'a': style = ReadWriteAppending;     break;
			case 'c': style = File.ReadWriteCreate;   break;
			default:
				throwStdException(t, "ValueException", "Unknown open mode '{}'", mode);
		}

		// TODO: figure out some way of making inout files buffered?
		auto f = safeCode(t, new File(name, style));

		lookupCT!("stream.InoutStream")(t);
		pushNull(t);
		pushNativeObj(t, f);
		rawCall(t, -3, 1);

		return 1;
	}

	uword rename(CrocThread* t)
	{
		safeCode(t, Path.rename(checkStringParam(t, 1), checkStringParam(t, 2)));
		return 0;
	}

	uword remove(CrocThread* t)
	{
		safeCode(t, Path.remove(checkStringParam(t, 1)));
		return 0;
	}

	uword copy(CrocThread* t)
	{
		safeCode(t, Path.copy(checkStringParam(t, 1), checkStringParam(t, 2)));
		return 0;
	}

	uword size(CrocThread* t)
	{
		pushInt(t, cast(crocint)safeCode(t, Path.fileSize(checkStringParam(t, 1))));
		return 1;
	}

	uword exists(CrocThread* t)
	{
		pushBool(t, Path.exists(checkStringParam(t, 1)));
		return 1;
	}

	uword isFile(CrocThread* t)
	{
		pushBool(t, safeCode(t, !Path.isFolder(checkStringParam(t, 1))));
		return 1;
	}

	uword isDir(CrocThread* t)
	{
		pushBool(t, safeCode(t, Path.isFolder(checkStringParam(t, 1))));
		return 1;
	}

	uword isReadOnly(CrocThread* t)
	{
		pushBool(t, safeCode(t, !Path.isWritable(checkStringParam(t, 1))));
		return 1;
	}

	uword fileTime(char[] which)(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto time = safeCode(t, mixin("Path." ~ which ~ "(checkStringParam(t, 1))"));
		word tab;

		if(numParams == 1)
			tab = newTable(t);
		else
		{
			checkParam(t, 2, CrocValue.Type.Table);
			tab = 2;
		}

		TimeLib.DateTimeToTable(t, WallClock.toDate(time), tab);
		dup(t, tab);
		return 1;
	}

	uword currentDir(CrocThread* t)
	{
		pushString(t, safeCode(t, Environment.cwd()));
		return 1;
	}

	uword parentDir(CrocThread* t)
	{
		auto p = optStringParam(t, 1, ".");

		if(p == ".")
			p = Environment.cwd();

		auto pp = safeCode(t, Path.parse(p));

		if(pp.isAbsolute)
			pushString(t, safeCode(t, Path.pop(p)));
		else
			pushString(t, safeCode(t, Path.join(Environment.cwd(), p)));

		return 1;
	}

	uword changeDir(CrocThread* t)
	{
		safeCode(t, Environment.cwd(checkStringParam(t, 1)));
		return 0;
	}

	uword makeDir(CrocThread* t)
	{
		auto p = Path.parse(checkStringParam(t, 1));

		if(!p.isAbsolute())
			safeCode(t, Path.createFolder(Path.join(Environment.cwd(), p.toString())));
		else
			safeCode(t, Path.createFolder(p.toString()));

		return 0;
	}

	uword makeDirChain(CrocThread* t)
	{
		auto p = Path.parse(checkStringParam(t, 1));

		if(!p.isAbsolute())
			safeCode(t, Path.createPath(Path.join(Environment.cwd(), p.toString())));
		else
			safeCode(t, Path.createPath(p.toString()));

		return 0;
	}

	uword removeDir(CrocThread* t)
	{
		safeCode(t, Path.remove(checkStringParam(t, 1)));
		return 0;
	}

	uword listImpl(CrocThread* t, bool isFolder)
	{
		auto numParams = stackSize(t) - 1;
		auto fp = optStringParam(t, 1, ".");

		if(fp == ".")
			fp = Environment.cwd();

		if(numParams >= 3)
		{
			auto filter = checkStringParam(t, 2);
			checkParam(t, 3, CrocValue.Type.Function);

			safeCode(t,
			{
				foreach(ref info; Path.children(fp))
				{
					if(info.folder is isFolder)
					{
						if(!Path.patternMatch(info.name, filter))
							continue;

						dup(t, 3);
						pushNull(t);
						pushString(t, info.path);
						pushString(t, info.name);
						cat(t, 2);
						rawCall(t, -3, 1);
						
						if(isBool(t, -1) && !getBool(t, -1))
							break;

						pop(t);
					}
				}
			}());
		}
		else
		{
			checkParam(t, 2, CrocValue.Type.Function);

			safeCode(t,
			{
				foreach(ref info; Path.children(fp))
				{
					if(info.folder is isFolder)
					{
						dup(t, 2);
						pushNull(t);
						pushString(t, info.path);
						pushString(t, info.name);
						cat(t, 2);
						rawCall(t, -3, 1);
						
						if(isBool(t, -1) && !getBool(t, -1))
							break;
							
						pop(t);
					}
				}
			}());
		}

		return 0;
	}

	uword listFiles(CrocThread* t)
	{
		return listImpl(t, false);
	}

	uword listDirs(CrocThread* t)
	{
		return listImpl(t, true);
	}

	uword readFile(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto shouldConvert = optBoolParam(t, 2, false);

		if(shouldConvert)
		{
			safeCode(t,
			{
				auto data = cast(ubyte[]).File.get(name);

				scope(exit)
					delete data;

				foreach(ref c; data)
					if(c > 0x7f)
						c = '\u001a';

				pushString(t, cast(char[])data);
			}());
		}
		else
		{
			safeCode(t,
			{
				scope file = new UnicodeFile!(char)(name, Encoding.Unknown);
				pushString(t, file.read());
			}());
		}

		return 1;
	}

	uword writeFile(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto data = checkStringParam(t, 2);

		safeCode(t,
		{
			scope file = new UnicodeFile!(char)(name, Encoding.UTF_8);
			file.write(data, true);
		}());

		return 0;
	}

	uword readMemblock(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto size = safeCode(t, Path.fileSize(name));

		if(size > uword.max)
			throwStdException(t, "ValueException", "file too big ({} bytes)", size);

		newMemblock(t, "u8", cast(uword)size);
		auto mb = getMemblock(t, -1);
		safeCode(t, File.get(name, mb.data[0 .. cast(uword)size]));
		return 1;
	}

	uword writeMemblock(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		checkParam(t, 2, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 2);
		safeCode(t, File.set(name, mb.data));
		return 1;
	}

	uword linesIterator(CrocThread* t)
	{
		auto lines = checkInstParam!(InStreamObj.Members)(t, 0, "stream.InStream").lines;
		auto index = checkIntParam(t, 1) + 1;
		auto line = safeCode(t, lines.next());

		if(line.ptr is null)
		{
			dup(t, 0);
			pushNull(t);
			methodCall(t, -2, "close", 0);
			return 0;
		}

		pushInt(t, index);
		pushString(t, line);
		return 2;
	}

	uword lines(CrocThread* t)
	{
		checkStringParam(t, 1);

		pushGlobal(t, "inFile");
		pushNull(t);
		dup(t, 1);
		rawCall(t, -3, 1);

		pushInt(t, 0);
		getUpval(t, 0);
		insert(t, -3);

		return 3;
	}

	uword join(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkAnyParam(t, 1);
		
		char[][] tmp;

		scope(exit)
			delete tmp;

		for(uword i = 1; i <= numParams; i++)
			tmp ~= checkStringParam(t, i);

		pushString(t, safeCode(t, Path.join(tmp)));
		return 1;
	}
	
	uword dirName(CrocThread* t)
	{
		pushString(t, safeCode(t, Path.parse(checkStringParam(t, 1))).path);
		return 1;
	}

	uword name(CrocThread* t)
	{
		pushString(t, safeCode(t, Path.parse(checkStringParam(t, 1))).name);
		return 1;
	}

	uword extension(CrocThread* t)
	{
		pushString(t, safeCode(t, Path.parse(checkStringParam(t, 1))).ext);
		return 1;
	}

	uword fileName(CrocThread* t)
	{
		pushString(t, safeCode(t, Path.parse(checkStringParam(t, 1))).file);
		return 1;
	}
}