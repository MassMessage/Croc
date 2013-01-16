/******************************************************************************
This module contains the 'stream' standard library.

License:
Copyright (c) 2013 Jarrett Billingsley

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

module croc.stdlib_stream;

import tango.io.model.IConduit;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_format;
import croc.ex_library;
import croc.types;
import croc.vm;

// =====================================================================================================================
// Public
// =====================================================================================================================

public:

void initStreamLib(CrocThread* t)
{
	newTable(t);
		registerFields(t, _funcs);
	newGlobal(t, "_streamtmp");

	importModuleFromStringNoNS(t, "stream", Code, __FILE__);

	pushGlobal(t, "_G");
	pushString(t, "_streamtmp");
	removeKey(t, -2);
	pop(t);
}

// =====================================================================================================================
// Private
// =====================================================================================================================

private:

const RegisterFunc[] _funcs =
[
	{ "streamCtor",  &_streamCtor,  maxParams: 4 },
	{ "streamRead",  &_streamRead,  maxParams: 4 },
	{ "streamWrite", &_streamWrite, maxParams: 4 },
	{ "streamSeek",  &_streamSeek,  maxParams: 3 },
	{ "streamFlush", &_streamFlush, maxParams: 0 },
	{ "streamClose", &_streamClose, maxParams: 0 }
];

uword _streamCtor(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.NativeObj);
	auto stream = getNativeObj(t, 1);
	auto closable = optBoolParam(t, 2, true);
	auto haveReadable = isValidIndex(t, 3);
	auto readable = haveReadable ? checkBoolParam(t, 3) : false;
	auto haveWritable = isValidIndex(t, 4);
	auto writable = haveWritable ? checkBoolParam(t, 4) : false;

	field(t, 0, "NativeStream_stream");

	if(!isNull(t, -1))
		throwStdException(t, "StateException", "Attempting to call constructor on an already-initialized stream");

	pop(t);

	if(cast(IConduit)stream)
	{
		if(!haveReadable || !haveWritable)
			throwStdException(t, "TypeException", "Both readable and writable parameters must be provided with an IConduit");
	}
	else if(cast(InputStream)stream)
		readable = true;
	else if(cast(OutputStream)stream)
		writable = true;
	else
		throwStdException(t, "TypeException", "stream parameter does not implement any of the valid Tango interfaces");

	dup(t, 1);             fielda(t, 0, "NativeStream_stream");
	pushBool(t, readable); fielda(t, 0, "NativeStream_readable");
	pushBool(t, writable); fielda(t, 0, "NativeStream_writable");
	pushBool(t, closable); fielda(t, 0, "NativeStream_closable");

	if(cast(IConduit.Seek)stream)
	{
		pushBool(t, true);
		fielda(t, 0, "NativeStream_seekable");
	}

	pushNull(t);
	pushNull(t);
	superCall(t, -2, "constructor", 0);

	return 0;
}

uword _streamRead(CrocThread* t)
{
	auto stream = cast(InputStream)getNativeObj(t, 1); assert(stream !is null);
	auto offset = cast(uword)getInt(t, 3);
	auto size = cast(uword)getInt(t, 4);
	auto dest = cast(void*)(getMemblockData(t, 2).ptr + offset);

	auto initial = size;

	while(size > 0)
	{
		auto numRead = safeCode(t, "exceptions.IOException", stream.read(dest[0 .. size]));

		if(numRead == IOStream.Eof)
			break;
		else if(numRead < size)
		{
			size -= numRead;
			break;
		}

		size -= numRead;
		dest += numRead;
	}

	pushInt(t, initial - size);
	return 1;
}

uword _streamWrite(CrocThread* t)
{
	auto stream = cast(OutputStream)getNativeObj(t, 1); assert(stream !is null);
	auto offset = cast(uword)getInt(t, 3);
	auto size = cast(uword)getInt(t, 4);
	auto src = cast(void*)(getMemblockData(t, 2).ptr + offset);

	auto initial = size;

	while(size > 0)
	{
		auto numWritten = safeCode(t, "exceptions.IOException", stream.write(src[0 .. size]));

		if(numWritten == IOStream.Eof)
		{
			lookup(t, "EOFException");
			pushNull(t);
			pushString(t, "End-of-flow encountered while writing");
			rawCall(t, -3, 1);
			throwException(t);
		}

		size -= numWritten;
		src += numWritten;
	}

	pushInt(t, initial);
	return 1;
}

uword _streamSeek(CrocThread* t)
{
	auto stream = cast(IOStream)getNativeObj(t, 1); assert(stream !is null);
	auto offset = getInt(t, 2);
	auto whence = getChar(t, 3);
	auto realWhence =
		whence == 'b' ? IOStream.Anchor.Begin :
		whence == 'c' ? IOStream.Anchor.Current :
		IOStream.Anchor.End;

	pushInt(t, safeCode(t, "exceptions.IOException", stream.seek(offset, realWhence)));
	return 1;
}

uword _streamFlush(CrocThread* t)
{
	auto stream = cast(IOStream)getNativeObj(t, 1); assert(stream !is null);
	safeCode(t, "exceptions.IOException", stream.flush());
	return 0;
}

uword _streamClose(CrocThread* t)
{
	auto stream = cast(IOStream)getNativeObj(t, 1); assert(stream !is null);
	safeCode(t, "exceptions.IOException", stream.close());
	return 0;
}

const Code =
`/**
This module contains Croc's streamed input/output framework. The base class for all data streams, \link{Stream}, as well
as several useful subclasses and helpers are defined in this module.

This module is safe. The \link{NativeStream} class does let scripts read and write data outside memory, but only the
host can create instances of it.
*/
module stream

import exceptions:
	BoundsException,
	IOException,
	NotImplementedException,
	RangeException,
	StateException,
	TypeException,
	ValueException

import math: min
import object: Finalizable
import text

local streamCtor = _streamtmp.streamCtor
local streamRead = _streamtmp.streamRead
local streamWrite = _streamtmp.streamWrite
local streamSeek = _streamtmp.streamSeek
local streamFlush = _streamtmp.streamFlush
local streamClose = _streamtmp.streamClose

local function clamp(x, lo, hi) =
	x < lo ? lo : x > hi ? hi : x

/**
An exception type derived from \tt{IOException} thrown in some APIs when end-of-file is reached.
*/
class EOFException : IOException
{
	///
	this()
		super("Unexpected end of file")
}

/**
An exception type derived from \tt{IOException} thrown in some APIs when stream protocols (behavior,
return values etc.) are not respected.
*/
class StreamProtocolException : IOException
{
	///
	this(msg: string)
		super("Stream protocol error: " ~ msg)
}

/**
A helper function for checking the params to stream \tt{read} and \tt{write} functions.

This ensures that the \tt{offset} and \tt{size} parameters are valid, and throws exceptions if not.

\throws[exceptions.BoundsException] if either \tt{offset} or \tt{size} is invalid.
*/
function checkRWParams(m, offset, size)
{
	if(offset < 0 || offset > #m)
		throw BoundsException("Invalid offset {} in memblock of size {}".format(offset, #m))

	if(size < 0 || size > #m - offset)
		throw BoundsException("Invalid size {} in memblock of size {} starting from offset {}".format(size, #m, offset))
}

local checkRWParams = checkRWParams

/**
The base class for stream-based IO.

This class defines the interface that all streams must implement, as well as some helper functions which are implemented
in terms of the user-defined methods. This interface is fairly low-level and is meant to be wrapped by higher-level
stream wrappers and filters.

There are a relatively small number of functions which must be implemented to satisfy the stream interface. Detailed
descriptions of these methods and their behavior is given inside this class, but a quick overview is as follows:

\blist
	\li \b{\tt{readable, writable, seekable}} - These simply return bools which indicate whether this stream can be read
		from, written to, and seeked.
	\li \b{\tt{read, write, seek}} - The real workhorse functions which actually perform the reading, writing, and
		seeking of the stream. Each of these only needs to be implemented if the corresponding \tt{-able} method returns
		\tt{true}.
	\li \b{\tt{flush, close, isOpen}} - Miscellaneous optional methods.
\endlist

For any given stream, likely only the first six (or some subset thereof) will have to be implemented.
*/
class Stream
{
	_scratch

	/**
	Constructor. Be sure to call this as \tt{super()} in classes derived from \link{Stream}. While it only checks
	that one of \link{readable} and \link{writable} returns true right now, this may change in the future.

	\throws[exceptions.IOException] if both \link{readable} and \link{writable} return \tt{false}.
	*/
	this()
	{
		if(!:readable() && !:writable())
			throw IOException("Stream is neither readable nor writable!")
	}

	/**
	Reads data from the stream into the given memblock.

	\param[this] must be readable.
	\param[m] is the memblock into which data will be read.
	\param[offset] is the offset into \tt{m} where the first byte of data will be placed. Defaults to 0.
	\param[size] is the number of bytes to read. Defaults to the size of \tt{m} minus the \tt{offset}.

	\returns an integer.

	\blist
		\li If \tt{size} is 0, this function is a no-op, and the return value is 0.
		\li If \tt{size} is nonzero,
		\blist
			\li If the read is successful, the return value is an integer in the range \tt{[1, size]} and indicates
				the number of bytes actually read. Fewer than \tt{size} bytes can be read in a number of non-error
				situations. If you need to fill up a buffer, make repeated calls to \tt{read} until the desired number
				of bytes has been read. The \link{readExact} method does this for you.
			\li If the stream has reached the end of the file, the return value is 0.
		\endlist
	\endlist

	\throws[exceptions.BoundsException] if the \tt{offset} is outside the range \tt{[0, #m]}, or if \tt{size}
	is outside the range \tt{[0, #m - offset]}.

	\throws[exceptions.IOException] or a derived class if some error occurred.
	*/
	function read(this: @InStream, m: memblock, offset: int = 0, size: int = #m - offset)
		throw NotImplementedException()

	/**
	Writes data into the stream from the given memblock.

	\param[this] must be writable.
	\param[m] is the memblock from which data will be written.
	\param[offset] is the offset into \tt{m} where the first byte of data will be retrieved. Defaults to 0.
	\param[size] is the number of bytes to write. Defaults to the size of \tt{m} minus the \tt{offset}.

	\returns an integer.

	\blist
		\li If \tt{size} is 0, this function is a no-op, and the return value is 0.
		\li If \tt{size} is nonzero and the write is successful, the return value is an integer in the range
			\tt{[1, size]} and indicates the number of bytes actually written. Fewer than \tt{size} bytes can be written
			in a number of non-error situations. If you need to write a whole buffer, make repeated calls to \tt{write}
			until the desired number of bytes has been written. The \link{writeExact} method does this for you.
	\endlist

	\throws[exceptions.BoundsException] if the \tt{offset} is outside the range \tt{[0, #m]}, or if \tt{size}
	is outside the range \tt{[0, #m - offset]}.

	\throws[exceptions.IOException] or a derived class if some error occurred.
	\throws[EOFException] if end-of-file was reached.
	*/
	function write(this: @OutStream, m: memblock, offset: int = 0, size: int = #m - offset)
		throw NotImplementedException()

	/**
	Changes the position of the stream's read/write position, and reports the new position once changed.

	Seeking past the end of a stream may or may not be an error, depending on the kind of stream.

	\param[this] must be seekable.
	\param[offset] is the position offset, whose meaning depends upon the \tt{where} parameter.
	\param[where] is a character indicating the position in the stream from which the new stream position will be
		calculated. It can be one of the three following values:

	\dlist
		\li{\b{\tt{'b'}}} The \tt{offset} is treated as an absolute offset from the beginning of the stream.
		\li{\b{\tt{'c'}}} The \tt{offset} is treated as a relative offset from the current read/write position. This
			means that negative \tt{offset} values move the read/write position backwards.
		\li{\b{\tt{'e'}}} The \tt{offset} is treated as a relative offset from the end of the stream.
	\endlist

	\returns the new stream position as an absolute position from the beginning of the stream.

	\throws[exceptions.IOException] if the resulting stream position would be negative, or if some error occurred.
	*/
	function seek(this: @SeekStream, offset: int, where: char)
		throw NotImplementedException()

	/**
	Tells whether or not \link{read} can be called on this stream.
	\returns a bool indicating such. The default implementation returns \tt{false}.
	*/
	function readable() = false

	/**
	Tells whether or not \link{write} can be called on this stream.
	\returns a bool indicating such. The default implementation returns \tt{false}.
	*/
	function writable() = false

	/**
	Tells whether or not \link{seek} can be called on this stream.
	\returns a bool indicating such. The default implementation returns \tt{false}.
	*/
	function seekable() = false

	/**
	An optional method used to flush cached data to the stream.

	Often buffering schemes are used to improve IO performance, but such schemes mean that the stream and its backing
	store are often incoherent. This method is called to force coherency by flushing any buffered data and writing it
	into the backing store.

	The default implementation is simply to do nothing.
	*/
	function flush() {}

	/**
	An optional method used to close a stream by releasing any system resources associated with it and preventing any
	further use.

	This method should be allowed to be called more than once, but calls beyond the first should be no-ops.

	The default implementation is simply to do nothing.
	*/
	function close() {}

	/**
	An optional method used to check whether or not this stream has been closed.

	This goes along with the \link{close} method; once \link{close} has been called, this method should return
	\tt{false}.

	\returns a bool indicating whether or not this stream is still open. The default implementation simply returns
	\tt{true}.
	*/
	function isOpen() = true

	/**
	A helper method which attempts to read a block of data fully, making multiple calls to \link{read} as needed.

	Since \link{read} may not read all the data for a block in one call, this method exists to automatically make as
	many calls to \link{read} as needed to fill the requested block of data. The parameters are identical to those of
	\link{read}.

	\throws[exceptions.IOException] or a derived class if some error occurred.
	\throws[EOFException] if end-of-file was reached.
	*/
	function readExact(m: memblock, offset: int = 0, size: int = #m - offset)
	{
		checkRWParams(m, offset, size)
		local remaining = size

		while(remaining > 0)
		{
			local bytesRead = :read(m, offset, remaining)

			if(bytesRead == 0)
				throw EOFException()

			offset += bytesRead
			remaining -= bytesRead
		}
	}

	/**
	A helper method which attempts to write a block of data fully, making multiple calls to \link{write} as needed.

	Since \link{write} may not write all the data for a block in one call, this method exists to automatically make as
	many calls to \link{write} as needed to write the requested block of data. The parameters are identical to those of
	\link{write}.

	\throws[exceptions.IOException] or a derived class if some error occurred.
	\throws[EOFException] if end-of-file was reached.
	*/
	function writeExact(m: memblock, offset: int = 0, size: int = #m - offset)
	{
		checkRWParams(m, offset, size)
		local remaining = size

		while(remaining > 0)
		{
			local bytesWritten = :write(m, offset, remaining)
			offset += bytesWritten
			remaining -= bytesWritten
		}
	}

	/**
	Skips forward a given number of bytes.

	The stream need not be seekable in order to skip forward. If it is not seekable, data will simply be read into a
	scratch buffer and discarded until the desired number of bytes have been skipped. If it is seekable, this will
	simply call \link{seek} to seek forward \tt{dist} bytes.

	\param[this] must be readable, and may optionally be seekable.
	\param[dist] is the number of bytes to skip. Can be 0.

	\throws[exceptions.RangeException] if \tt{dist} is negative.
	\throws[exceptions.IOException] or a derived class if some error occurred.
	\throws[EOFException] if end-of-file was reached.
	*/
	function skip(this: @InStream, dist: int)
	{
		if(dist < 0)
			throw RangeException("Invalid skip distance ({})".format(dist))
		else if(dist == 0)
			return

		if(:seekable())
		{
			:seek(dist, 'c')
			return
		}

		:flush()

		:_scratch ?= memblock.new(4096)
		local buf = :_scratch

		while(dist > 0)
		{
			local bytesRead = :readExact(buf, 0, min(dist, #buf))

			if(bytesRead == 0)
				throw EOFException()

			dist -= numBytes
		}
	}

	/**
	Reads all remaining data from the stream up to end-of-file into a memblock.

	This will call \link{read} as many times as needed until it indicates that the end of file has been reached.

	\param[this] must be readable.
	\param[m] is an optional memblock to use as the buffer to hold the read data. If one is given, it will be resized to
		hold the read data. If it is not given, a new memblock will be used instead.

	\returns the memblock holding the read data.
	*/
	function readAll(this: @InStream, m: memblock = null)
	{
		if(m is null)
			m = memblock.new(4096)
		else if(#m < 4096)
			#m = 4096

		local offs = 0

		while(true)
		{
			local numBytes = :read(m, offs)

			if(numBytes == 0)
				break

			offs += numBytes

			if(#m < offs + 4096)
				#m = offs + 4096
		}

		#m = offs
		return m
	}

	/**
	Copies data from another stream into this one.

	The data is copied in blocks of 4096 bytes at a time.

	\param[this] must be writable.
	\param[s] is the source stream from which the data will be read, and must be readable.
	\param[size] is the number of bytes to copy, or -1 to mean all data until \tt{s} reaches end-of-file.

	\throws[exceptions.RangeException] if \tt{size < -1}.
	\throws[EOFException] if \tt{size > 0} and end-of-file was reached before copying could finish.
	*/
	function copy(this: @OutStream, s: @InStream, size: int = -1)
	{
		:_scratch ?= memblock.new(4096)
		local buf = :_scratch

		if(size < -1)
			throw RangeException("Invalid size: {}".format(size))

		if(size == -1)
		{
			while(true)
			{
				local numRead = s.read(buf)

				if(numRead == 0)
					break

				:writeExact(buf, 0, numRead)
			}
		}
		else
		{
			local remaining = size

			while(remaining > 0)
			{
				local numRead = s.read(buf, 0, min(remaining, #buf))

				if(numRead == 0)
					throw EOFException()

				:writeExact(buf, 0, numRead)
				remaining -= numRead
			}
		}
	}

	/**
	Sets or gets the absolute position in the stream, as a convenience.

	\param[this] must be seekable.
	\param[pos] is either the new read/write position, measured in bytes from the beginning of the stream, or \tt{null}.

	\returns the new position if \tt{pos} was non-null, or the current position if \tt{pos} was \tt{null}.
	*/
	function position(this: @SeekStream, pos: int|null)
	{
		if(pos is null)
			return :seek(0, 'c')
		else
			return :seek(pos, 'b')
	}

	/**
	Returns the size of the stream in bytes.

	It does this by seeking to the end of the stream and getting the position, then seeking back to where it was before
	calling this method. As a result this method can cause buffered data to be flushed.

	\param[this] must be seekable.

	\returns an integer indicating how many bytes long this stream is.
	*/
	function size(this: @SeekStream)
	{
		local pos = :position()
		local ret = :seek(0, 'e')
		:position(pos)
		return ret
	}
}

/**
These are meant to be used as custom parameter type constraints, to ensure that a stream parameter supports certain
operations.

All of these ensure that \tt{s} is derived from \link{Stream}. The \tt{in} functions ensure that \tt{s.readable()}
returns true; the \tt{out} functions ensure that \tt{s.writable()} returns true; and the \tt{seek} functions ensure that
\tt{s.seekable()} returns true. An example of use:

\code
// Expects the dest stream to be writable and the src stream to be readable
function copyBlock(dest: @OutStream, src: @InStream) { ... }

// Finds the directory section in a ZIP file and reads it; expects the stream to be readable and seekable.
function readZIPDirectory(s: @InSeekStream) { ... }
\endcode

It's a good idea to use only what you need and not over-request features; for instance, if you're never going to write
to the stream, don't use an \tt{out} function.

\param[s] the stream object to test.
\returns a bool telling whether or not it satisfies the constraints.
*/
function InStream(s) =        s as Stream && s.readable()
function OutStream(s) =       s as Stream &&                 s.writable()                 /// ditto
function InoutStream(s) =     s as Stream && s.readable() && s.writable()                 /// ditto
function SeekStream(s) =      s as Stream &&                                 s.seekable() /// ditto
function InSeekStream(s) =    s as Stream && s.readable() &&                 s.seekable() /// ditto
function OutSeekStream(s) =   s as Stream &&                 s.writable() && s.seekable() /// ditto
function InoutSeekStream(s) = s as Stream && s.readable() && s.writable() && s.seekable() /// ditto

/**
This is meant to be used as a custom parameter type constraint. It ensures that its parameter is derived from
\link{Stream} and that its \link[Stream.isOpen]{\tt{isOpen} method} returns \tt{true}.

\param[s] the stream object to test.
\returns a bool telling whether or not it satisfies the constraints.
*/
function OpenStream(s) = s as Stream && s.isOpen()

/**
Implements a readable, writable, seekable stream that uses a memblock as its data backing store.

This is a very useful kind of stream. With it you can redirect stream operations that would normally go to a file to
memory instead. It can often be much faster to read in a large chunk of a file, or a file in its entirety, and then do
processing in memory. This is also useful for building up data to be sent over networks or such.

The backing memblock can be one you provide, or it can use its own. The memblock will be grown automatically when data
is written past its end.
*/
class MemblockStream : Stream
{
	_mb
	_pos = 0

	/**
	Constructor.

	\param[mb] is the memblock to use as the backing store. If none is given, a new zero-size memblock will be used
	instead.
	*/
	this(mb: memblock = memblock.new(0))
	{
		:_mb = mb
		super()
	}

	/**
	Implmentation of \link{Stream.read}.
	*/
	function read(m: memblock, offset: int = 0, size: int = #m - offset)
	{
		if(:_pos >= #:_mb)
			return 0

		checkRWParams(m, offset, size)

		if(size == 0)
			return 0

		local numBytes = min(size, #:_mb - :_pos)
		m.copy(offset, :_mb, :_pos, numBytes)
		:_pos += numBytes
		return numBytes
	}

	/**
	Implmentation of \link{Stream.write}.

	If there is not enough space in the memblock to hold the new data, the memblock's size will be expanded to
	accommodate.
	*/
	function write(m: memblock, offset: int = 0, size: int = #m - offset)
	{
		checkRWParams(m, offset, size)

		if(size == 0)
			return 0

		local bytesLeft = #:_mb - :_pos

		if(size > bytesLeft)
			#:_mb += size - bytesLeft

		:_mb.copy(:_pos, m, offset, size)
		:_pos += size
		return size
	}

	/**
	Implmentation of \link{Stream.seek}.

	If you seek past the end of the memblock, the memblock will be resized to the new offset. This is to match the
	behavior of seeking on files.

	\throws[exceptions.ValueException] if \tt{where} is invalid.
	\throws[exceptions.IOException] if the resulting offset is negative.
	*/
	function seek(offset: int, where: char)
	{
		switch(where)
		{
			case 'b': break
			case 'c': offset += :_pos; break
			case 'e': offset += #:_mb; break
			default: throw ValueException("Invalid seek type '{}'".format(where))
		}

		if(offset < 0)
			throw IOException("Invalid seek offset")

		if(offset > #:_mb)
			#:_mb = offset

		:_pos = offset
		return offset
	}

	/**
	Implementations of \link{Stream.readable}, \link{Stream.writable}, and \link{Stream.seekable}. All return true.
	*/
	function readable() = true
	function writable() = true /// ditto
	function seekable() = true /// ditto

	/**
	Gets the backing memblock.

	It's probably best not to change the size of the memblock while it's still being used by the stream.

	\returns the backing memblock.
	*/
	function getBacking() = :_mb
}

/**
A base class for types of streams which expand the capabilities of another stream without obscuring the underlying
stream interface.

It takes a stream object and implements all of the \link{Stream} interface methods as simply passthroughs to the
underlying stream object. Subclasses can then add methods and possibly override just those which they need to.
*/
class StreamWrapper : Stream
{
	_stream

	/**
	Constructor.

	\param[s] is the stream object to be wrapped.
	*/
	this(s: Stream)
	{
		:_stream = s
		super()
	}

	/**
	These all simply pass through functionality to the wrapped stream object.
	*/
	function read(m, off, size) = :_stream.read(m, off, size)
	function write(m, off, size) = :_stream.write(m, off, size) /// ditto
	function seek(off, where) = :_stream.seek(off, where)       /// ditto
	function flush() = :_stream.flush()                         /// ditto
	function close() = :_stream.close()                         /// ditto
	function isOpen() = :_stream.isOpen()                       /// ditto
	function readable() = :_stream.readable()                   /// ditto
	function writable() = :_stream.writable()                   /// ditto
	function seekable() = :_stream.seekable()                   /// ditto

	/**
	Gets the stream that this instance wraps.

	\returns the same stream object that was passed to the constructor.
	*/
	function getWrappedStream() = :_stream
}

/**
A kind of stream wrapper class that adds a simple interface for reading and writing binary data.

Because it's a stream wrapper, the basic stream interface can still be used on it and the functionality will be passed
through to the wrapped stream.
*/
class BinaryStream : StreamWrapper
{
	_rwBuf
	_strBuf

	/**
	Constructor.

	\param[s] is the stream to be wrapped.
	*/
	this(s: Stream)
	{
		super(s)
		:_rwBuf = memblock.new(8)
		:_strBuf = memblock.new(0)
	}

	/**
	These all read a single integer or floating-point value of the given type and size.

	Note that because Croc's \tt{int} type is a signed 64-bit integer, \tt{readUInt64} will return negative numbers for
	those that exceed 2\sup{63} - 1. It exists for completeness.

	\returns an \tt{int} or \tt{float} representing the value read.
	\throws[EOFException] if end-of-file was reached.
	*/
	function readInt8()    { :_stream.readExact(:_rwBuf, 0, 1); return :_rwBuf.readInt8(0)    }
	function readInt16()   { :_stream.readExact(:_rwBuf, 0, 2); return :_rwBuf.readInt16(0)   } /// ditto
	function readInt32()   { :_stream.readExact(:_rwBuf, 0, 4); return :_rwBuf.readInt32(0)   } /// ditto
	function readInt64()   { :_stream.readExact(:_rwBuf, 0, 8); return :_rwBuf.readInt64(0)   } /// ditto
	function readUInt8()   { :_stream.readExact(:_rwBuf, 0, 1); return :_rwBuf.readUInt8(0)   } /// ditto
	function readUInt16()  { :_stream.readExact(:_rwBuf, 0, 2); return :_rwBuf.readUInt16(0)  } /// ditto
	function readUInt32()  { :_stream.readExact(:_rwBuf, 0, 4); return :_rwBuf.readUInt32(0)  } /// ditto
	function readUInt64()  { :_stream.readExact(:_rwBuf, 0, 8); return :_rwBuf.readUInt64(0)  } /// ditto
	function readFloat32() { :_stream.readExact(:_rwBuf, 0, 4); return :_rwBuf.readFloat32(0) } /// ditto
	function readFloat64() { :_stream.readExact(:_rwBuf, 0, 8); return :_rwBuf.readFloat64(0) } /// ditto

	/**
	Reads a binary representation of a \tt{string} object. Should only be used as the inverse to \link{writeString}.

	\returns a \tt{string} representing the value read.
	\throws[EOFException] if end-of-file was reached.
	*/
	function readString()
	{
		local len = :readUInt64()
		#:_strBuf = len
		:stream.readExact(:_strBuf)
		return text.fromRawUnicode(:_strBuf)
	}

	/**
	Reads a given number of \b{ASCII} characters and returns them as a string.

	This is particularly useful for chunk identifiers in RIFF-type files and "magic numbers", though it can have other
	uses as well.

	\param[n] is the number of bytes to read.

	\returns a \tt{string} representing the characters read.

	\throws[exceptions.RangeException] if \tt{n < 1}.
	\throws[EOFException] if end-of-file was reached.
	*/
	function readChars(n: int)
	{
		if(n < 1)
			throw RangeException("Invalid number of characters ({})".format(n))

		#:_strBuf = n
		:stream.readExact(:_strBuf)
		return text.fromRawAscii(:_strBuf)
	}

	/**
	These all write a single integer or floating-point value of the given type and size.

	\param[x] is the value to write.
	\returns \tt{this}.
	\throws[EOFException] if end-of-file was reached.
	*/
	function writeInt8(x: int)      { :_rwbuf.writeInt8(0, x);    :_stream.writeExact(:_rwBuf, 0, 1); return this }
	function writeInt16(x: int)     { :_rwbuf.writeInt16(0, x);   :_stream.writeExact(:_rwBuf, 0, 2); return this }
	function writeInt32(x: int)     { :_rwbuf.writeInt32(0, x);   :_stream.writeExact(:_rwBuf, 0, 4); return this }
	function writeInt64(x: int)     { :_rwbuf.writeInt64(0, x);   :_stream.writeExact(:_rwBuf, 0, 8); return this }
	function writeUInt8(x: int)     { :_rwbuf.writeUInt8(0, x);   :_stream.writeExact(:_rwBuf, 0, 1); return this }
	function writeUInt16(x: int)    { :_rwbuf.writeUInt16(0, x);  :_stream.writeExact(:_rwBuf, 0, 2); return this }
	function writeUInt32(x: int)    { :_rwbuf.writeUInt32(0, x);  :_stream.writeExact(:_rwBuf, 0, 4); return this }
	function writeUInt64(x: int)    { :_rwbuf.writeUInt64(0, x);  :_stream.writeExact(:_rwBuf, 0, 8); return this }
	function writeFloat32(x: float) { :_rwbuf.writeFloat32(0, x); :_stream.writeExact(:_rwBuf, 0, 4); return this }
	function writeFloat64(x: float) { :_rwbuf.writeFloat64(0, x); :_stream.writeExact(:_rwBuf, 0, 8); return this }

	/**
	Writes a binary representation of the given string. To read this binary representation back again, use
	\link{readString}. The representation is a 64-bit unsigned integer indicating the length, in bytes, of the string
	data encoded in UTF-8, followed by the string data encoded in UTF-8.

	\param[x] is the string to write.
	\returns \tt{this}.
	\throws[EOFException] if end-of-file was reached.
	*/
	function writeString(x: string)
	{
		text.toRawUnicode(x, 8, :_strBuf)
		:writeUInt64(#:_strBuf)
		:stream.writeExact(:_strBuf)
		return this
	}

	/**
	Writes the given string, which must be ASCII only, as a raw sequence of byte-sized characters.

	This is particularly useful for chunk identifiers in RIFF-type files and "magic numbers", though it can have other
	uses as well.

	\param[x] is the string containing the characters to be written. It must be ASCII.
	\returns \tt{this}.
	\throws[exceptions.ValueException] if \tt{x} is not ASCII.
	\throws[EOFException] if end-of-file was reached.
	*/
	function writeChars(x: string)
	{
		if(!ascii.isAscii(x))
			throw ValueException("Can only write ASCII strings as raw characters")

		text.toRawAscii(x, :_strBuf)
		:stream.writeExact(:_strBuf)
		return this
	}
}

/**
A stream wrapper that adds input buffering. Note that this class only allows reading and seeking; writing is
unsupported.

This stream adds a transparent buffering scheme when reading data. Seeking is also allowed and will work correctly even
if data is buffered.
*/
class BufferedInStream : StreamWrapper
{
	_buf
	_bufPos = 0
	_bound = 0

	/**
	Constructor.

	\param[s] is the stream to be wrapped.
	\param[bufSize] is the size of the memory buffer. Defaults to 4KB. Its size is clamped to a minimum of 128 bytes,
	and there is no upper limit.
	*/
	this(s: @InStream, bufSize: int = 4096)
	{
		super(s)
		:_buf = memblock.new(clamp(bufSize, 128, intMax))
	}

	/**
	Regardless of whether or not the underlying stream is writable, this class is not. Erratic behavior can result if
	you try to write to a stream that is wrapped by this class.

	\returns false.
	*/
	function writable() =
		false

	/**
	Implementation of the \tt{read} method. It works exactly like the normal \tt{read} method, performing buffering
	transparently.

	The call signature and return values are the same as \link{Stream.read}.
	*/
	function read(m: memblock, offset: int = 0, size: int = #m - offset)
	{
		checkRWParams(m, offset, size)
		local remaining = size

		while(remaining > 0)
		{
			local buffered = :_bound - :_bufPos

			if(buffered == 0)
			{
				buffered = :_readMore()

				if(buffered == 0)
					break
			}

			local num = min(buffered, remaining)
			m.rawCopy(offset, :_buf, :_bufPos, num)
			:_bufPos += num
			offset += num
			remaining -= num
		}

		return size - remaining
	}

	/**
	Implementation of the \tt{seek} method. It works exactly like the normal \tt{seek} method, and will seek properly
	even if data has been buffered.

	Seeking will clear the data buffer. The call signature and return values are the same as \link{Stream.seek}.
	*/
	function seek(this: @SeekStream, offset: int, where: char)
	{
		if(where == 'c')
			offset -= :_bound - :_bufPos

		:_bufPos, :_bound = 0, 0
		return :_stream.seek(offset, where)
	}

	function _readMore()
	{
		assert((:_bound - :_bufPos) == 0)
		:_bufPos = 0
		:_bound = :_stream.read(:_buf)
		return :_bound
	}
}

/**
A stream wrapper that adds output buffering. Note that this class only allows writing and seeking; reading is
unsupported.

This stream adds a transparent buffering scheme when writing data. Seeking is also allowed and will work correctly even
if data is buffered.
*/
class BufferedOutStream : StreamWrapper
{
	_buf
	_bufPos = 0

	/**
	Constructor.

	\param[s] is the stream to be wrapped.
	\param[bufSize] is the size of the memory buffer. Defaults to 4KB. Its size is clamped to a minimum of 128 bytes,
	and there is no upper limit.
	*/
	this(s: @OutStream, bufSize: int = 4096)
	{
		super(s)
		:_buf = memblock.new(clamp(bufSize, 128, intMax))
	}

	/**
	Regardless of whether or not the underlying stream is readable, this class is not. Erratic behavior can result if
	you try to read from a stream that is wrapped by this class.

	\returns false.
	*/
	function readable() =
		false

	/**
	Implementation of the \tt{write} method. It works exactly like the normal \tt{write} method, performing buffering
	transparently.

	The call signature and return values are the same as \link{Stream.write}.
	*/
	function write(m: memblock, offset: int = 0, size: int = #m - offset)
	{
		checkRWParams(m, offset, size)
		local remaining = size

		while(remaining > 0)
		{
			local spaceLeft = #:_buf - :_bufPos

			if(spaceLeft == 0)
			{
				:flush()
				spaceLeft = #:_buf
			}

			local num = min(spaceLeft, remaining)
			:_buf.rawCopy(:_bufPos, m, offset, num)
			:_bufPos += num
			offset += num
			remaining -= num
		}

		return size - remaining
	}

	/**
	Implementation of the \tt{seek} method. It works exactly like the normal \tt{seek} method, and will seek properly
	even if data has been buffered.

	Seeking will flush the data buffer. The call signature and return values are the same as \link{Stream.seek}.
	*/
	function seek(offset: int, where: char)
	{
		if(where == 'c')
			offset -= :_bufPos

		if(:_bufPos > 0)
			:flush()

		return :_stream.seek(offset, where)
	}

	/**
	Implementation of the \tt{flush} method. This writes any buffered data to the stream. If no data is buffered, does
	nothing.

	\throws[EOFException] if end-of-file is reached.
	*/
	function flush()
	{
		if(:_bufPos > 0)
		{
			:_stream.write(:_buf, 0, :_bufPos)
			:_bufPos = 0
			:_stream.flush()
		}
	}

	/**
	Implementation of the \tt{close} method. Simply flushes the buffer and then calls \tt{close} on the underlying
	stream.
	*/
	function close()
	{
		:_flush()
		:_stream.close()
	}
}

/**
Implements a simple line-oriented text reader. You provide it with a stream and a character encoding to use, and it will
decode text data from the stream and return it one line at a time.

This class uses its own buffering mechanism, meaning that you do not have to place a buffer between it and the source
stream object.

This class does not implement the stream interface, nor is it a stream wrapper.
*/
class TextReader
{
	_stream
	_codec
	_readBuf
	_chunks
	_string = ""

	/**
	Constructor.

	\param[s] is the stream which will provide the data. It must be readable.
	\param[codec] is the name of the codec (see \link{text}) in which the stream data is encoded.
	\param[errors] is the error handling mode that will be passed to the text codec. Defaults to \tt{"strict"}.
	\param[bufSize] is the size of the internal buffer. Defaults to 4096 (4 KB). Its value is clamped to a minimum of
		128.
	*/
	this(s: @InStream, codec: string, errors: string = "strict", bufSize: int = 4096)
	{
		:_stream = s
		:_codec = text.getCodec(codec).incrementalDecoder(errors)
		:_readBuf = memblock.new(bufSize < 128 ? 128 : bufSize)
		:_chunks = []
	}

	/**
	Reads one line of text from the stream.

	\param[stripEnding] controls whether or not the line ending character(s) will be preserved in the output. This
		defaults to "true", in which case the line ending will be stripped and only the line's text will be returned.

	\returns a string containing one line of text, or if the end of the stream has been reached, returns \tt{null}.
	*/
	function readln(stripEnding: bool = true)
	{
		if(:_string is "")
		{
			:_readMore()

			if(:_string is "")
				return null
		}

		#:_chunks = 0

		while main(:_string !is "")
		{
			foreach(pos, c; :_string)
			{
				if(c == '\r' || c == '\n')
				{
					local nextLineStart

					if(c == '\r' && pos + 1 < #:_string && :_string[pos + 1] == '\n')
						nextLineStart = pos + 2
					else
						nextLineStart = pos + 1

					if(stripEnding)
						:_chunks ~= :_string[.. pos]
					else
						:_chunks ~= :_string[.. nextLineStart]

					:_string = :_string[nextLineStart ..]
					break main
				}
			}

			:_chunks ~= :_string
			:_string = ""
			:_readMore()
		}

		return "".join(:_chunks)
	}

	function stripIterator(idx: int)
	{
		if(local ret = :readln())
			return idx + 1, ret
	}

	function nostripIterator(idx: int)
	{
		if(local ret = :readln(false))
			return idx + 1, ret
	}

	/**
	Allows instances of this object to be used in \tt{foreach} loops. The first index is the 1-based index of the line,
	and the second index is the line's contents.

	\param[mode] is a string controlling whether or not line ending character(s) are stripped. The default is "strip"
		which removes them. The only other valid value is "nostrip" which preserves them.

	\examples

	Suppose you had a file with three lines, and you had a stream that read from that file. You could iterate over its
	lines like so:

\code
foreach(i, line; TextReader(fileStream))
	writefln("{}: {}", i, line)
\endcode

	This might print:

\verbatim
1: First line!
2: Second line.
3: Last liiiiine
\endverbatim
	*/
	function opApply(mode: string = "strip")
	{
		if(mode is "strip")
			return :stripIterator, this, 0
		else if(mode is "nostrip")
			return :nostripIterator, this, 0
		else
			throw ValueException("Invalid iteration mode '{}'".format(mode))
	}

	/**
	Reads all the remaining lines from the stream and returns them as an array of strings.

	\param[stripEnding] works just like in \link{readln}.
	\returns an array of strings, one for each line.
	*/
	function readAllLines(stripEnding: bool = true) =
		[line foreach line; this, stripEnding ? "strip" : "nostrip"]

	/**
	\returns the stream object that was passed to the constructor.
	*/
	function getStream() =
		:_stream

	function _readMore()
	{
		local numRead = :_stream.read(:_readBuf)

		if(numRead == 0)
			return

		local final = numRead < #:_readBuf
		:_string ~= :_codec.decodeRange(:_readBuf, 0, numRead, final)
	}
}

/**
Implements a simple line-oriented text writer with formatting support. You provide it with a stream and a character
encoding to use, and it will transparently encode text that you write. It can optionally flush the underlying stream at
each newline.

Unlike \link{TextReader}, this class does \em{not} use any buffering mechanism, so if you're using this to write a large
file for instance, it's best to put a buffer between this and the output stream.

This class does not implement the stream interface, nor is it a stream wrapper.
*/
class TextWriter
{
	_stream
	_codec
	_writeBuf
	_shouldFlush = false
	_newline

	/**
	Constructor.

	\param[s] is the stream to which data will be written. It must be writable.
	\param[codec] is the name of the codec (see \link{text}) in which the text will be encoded.
	\param[errors] is the error handling mode that will be passed to the text codec. Defaults to \tt{"strict"}.
	\param[newline] is the string which will be output to write a newline. Defaults to \tt{"\\n"}.
	*/
	this(s: @OutStream, codec: string, errors: string = "strict", newline: string = "\n")
	{
		:_stream = s
		:_codec = text.getCodec(codec).incrementalEncoder()
		:_writeBuf = memblock.new(0)
		:_newline = newline
	}

	/**
	Controls whether the underlying stream will be automatically flushed on newlines. This flushing behavior only
	happens after calls to \link{writeln} and \link{writefln}; it does not happen if there are newlines embedded in the
	output text.

	\param[f] is \tt{true} to enable this behavior, \tt{false} otherwise. By default, flushing is off.
	*/
	function flushOnNL(f: bool)
		:_shouldFlush = f

	/**
	Converts each argument to its string representation (with \link{toString}), encodes the string with the writer's
	encoding, and outputs it to the underlying stream.
	*/
	function write(vararg)
	{
		for(i: 0 .. #vararg)
			:_stream.write(:_codec.encodeInto(toString(vararg[i]), :_writeBuf, 0))
	}

	/**
	Same as above, but after outputting the arguments, outputs the newline string as specified in the constructor. After
	that, it will call the underlying stream's \tt{flush} method if newline flushing is enabled.
	*/
	function writeln(vararg)
	{
		:write(vararg)
		:write(:_newline)

		if(:_shouldFlush)
			:_stream.flush()
	}

	/**
	Equivalent to calling \tt{write(fmt.format(vararg))}.
	*/
	function writef(fmt: string, vararg)
		:_stream.write(:_codec.encodeInto(fmt.format(vararg), :_writeBuf, 0))

	/**
	Same as above, but outputs a newline and optionally flushes like \link{writeln}.
	*/
	function writefln(fmt: string, vararg)
	{
		:writef(fmt, vararg)
		:write(:_newline)

		if(:_shouldFlush)
			:_stream.flush()
	}

	/**
	\returns the stream object that was passed to the constructor.
	*/
	function getStream() =
		:_stream
}

/**
This class wraps a host language stream object. Because of this, its interface may vary between implementations of Croc.
This is the documentation for the D 1.0 implementation.

This class wraps objects of one of three of Tango's IO interfaces: \tt{InputStream}, \tt{OutputStream}, or
\tt{IConduit}. It also provides a "closability" option to prevent script code from closing streams it shouldn't have
permission to.
*/
@Finalizable
class NativeStream : Stream
{
	_stream
	_closed = false
	_readable
	_writable
	_seekable = false
	_closable
	_dirty = false

	/**
	Constructor.

	\param[stream] is a native object that must inherit from one of Tango's \tt{InputStream}, \tt{OutputStream}, or
		\tt{IConduit} interfaces. If it inherits from either of the first two, the \tt{readable} and \tt{writable}
		parameters will be ignored, and its read/writability will be automatically determined. If it inherits from
		\tt{IConduit}, you must provide both the \tt{readable} and \tt{writable} parameters. This is because Tango does
		not provide any means of determining whether an \tt{IConduit} really can be read or written (for instance, a
		\tt{File} opened in read-only mode is still "writable" according to the type system). Additionally, if this
		object derives from \tt{IConduit.Seek}, this stream will be seekable.
	\param[closable] tells whether or not script code will be allowed to close this stream. The default is \tt{true},
		but you can prevent scripts from closing a stream by passing \tt{false}. For instance, the \tt{console} library
		prevents scripts from closing the standard streams it creates.
	\param[readable] see the \tt{stream} parameter.
	\param[writable] see the \tt{stream} parameter.
	*/
	this(stream: nativeobj, closable: bool = true, readable: null|bool, writable: null|bool)
		streamCtor(with this, stream, closable, readable, writable)

	/**
	Finalizer. If the stream is writable, it will be flushed, and if it is closable, it will be closed.
	*/
	function finalizer()
	{
		if(:_writable) :_checkDirty()
		if(:_closable && !:_closed) :close()
	}

	/**
	Implementations of the main stream interface functions. These all expect the stream to be open.
	*/
	function read(this: @OpenStream, m: memblock, offset: int = 0, size: int = #m - offset)
	{
		:_checkReadable()
		if(:_writable) :_checkDirty()
		checkRWParams(m, offset, size)
		return streamRead(:_stream, m, offset, size)
	}

	/// ditto
	function write(this: @OpenStream, m: memblock, offset: int = 0, size: int = #m - offset)
	{
		:_checkWritable()
		checkRWParams(m, offset, size)
		return streamWrite(:_stream, m, offset, size)
	}

	/// ditto
	function seek(this: @OpenStream, offset: int, where: char)
	{
		:_checkSeekable()
		if(:_writable) :_checkDirty()

		if(where !in "bce")
			throw ValueException("Invalid seek location '{}'".format(where))

		return streamSeek(:_stream, offset, where)
	}

	/**
	Tells whether or not the stream is readable, writable, seekable, and closable.
	*/
	function readable() = :_readable
	function writable() = :_writable /// ditto
	function seekable() = :_seekable /// ditto
	function closable() = :_closable /// ditto

	/**
	Calls the underlying flush method of the stream.
	*/
	function flush(this: @OpenStream)
		streamFlush(:_stream)

	/**
	Closes the stream.

	\throws[exceptions.StateException] if you try to close a stream that was not set to be closable in the constructor.
	*/
	function close()
	{
		if(!:_closable)
			throw StateException("Trying to close an unclosable stream")

		streamClose(:_stream)
		:_closed = true
	}

	/**
	Tells whether or not the stream is open.
	*/
	function isOpen() =
		!:_closed

	function _checkReadable() { if(!:_readable) throw TypeException("Attempting to read from an unreadable stream") }
	function _checkWritable() { if(!:_writable) throw TypeException("Attempting to write to an unwritable stream") }
	function _checkSeekable() { if(!:_seekable) throw TypeException("Attempting to seek an unseekable stream") }

	function _checkDirty()
	{
		if(:_dirty)
		{
			:flush()
			:_dirty = false
		}
	}
}
`;