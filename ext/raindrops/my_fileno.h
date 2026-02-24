#include <ruby.h>
#include <ruby/io.h>

static int my_fileno(VALUE io)
{
	if (TYPE(io) != T_FILE)
		io = rb_convert_type(io, T_FILE, "IO", "to_io");

	return rb_io_descriptor(io);
}
