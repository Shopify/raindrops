require 'mkmf'
require 'shellwords'

have_func('mmap', 'sys/mman.h') or abort 'mmap() not found'
have_func('munmap', 'sys/mman.h') or abort 'munmap() not found'

$CPPFLAGS += " -D_GNU_SOURCE "
have_func('mremap', 'sys/mman.h')
headers = %w(sys/types.h netdb.h string.h sys/socket.h netinet/in.h)
if have_header('linux/tcp.h')
  headers << 'linux/tcp.h'
else
  %w(netinet/tcp.h netinet/tcp_fsm.h).each { |h|
    have_header(h, headers) and headers << h
  }
end

$CPPFLAGS += " -D_DEFAULT_SOURCE "

if have_type("struct tcp_info", headers)
  %w(
    tcpi_state
    tcpi_ca_state
    tcpi_retransmits
    tcpi_probes
    tcpi_backoff
    tcpi_options
    tcpi_snd_wscale
    tcpi_rcv_wscale
    tcpi_rto
    tcpi_ato
    tcpi_snd_mss
    tcpi_rcv_mss
    tcpi_unacked
    tcpi_sacked
    tcpi_lost
    tcpi_retrans
    tcpi_fackets
    tcpi_last_data_sent
    tcpi_last_ack_sent
    tcpi_last_data_recv
    tcpi_last_ack_recv
    tcpi_pmtu
    tcpi_rcv_ssthresh
    tcpi_rtt
    tcpi_rttvar
    tcpi_snd_ssthresh
    tcpi_snd_cwnd
    tcpi_advmss
    tcpi_reordering
    tcpi_rcv_rtt
    tcpi_rcv_space
    tcpi_total_retrans
    tcpi_snd_wnd
    tcpi_snd_bwnd
    tcpi_snd_nxt
    tcpi_rcv_nxt
    tcpi_toe_tid
    tcpi_snd_rexmitpack
    tcpi_rcv_ooopack
    tcpi_snd_zerowin
  ).each do |field|
    cfunc = "tcp_info_#{field}"
    if have_struct_member('struct tcp_info', field, headers)
      func_body = <<EOF
static VALUE #{cfunc}(VALUE self)
{
	struct tcp_info *info = DATA_PTR(self);
	return UINT2NUM((uint32_t)info->#{field});
}
EOF
      func_body.delete!("\n")
      $defs << "-DCFUNC_#{cfunc}=#{Shellwords.shellescape(func_body)}"
    else
      func_body = "static inline void #{cfunc}(void) {}"
      $defs << "-DCFUNC_#{cfunc}=#{Shellwords.shellescape(func_body)}"
      cfunc = 'rb_f_notimplement'.freeze
    end
    rbmethod = %Q("#{field.sub(/\Atcpi_/, ''.freeze)}")
    $defs << "-DDEFINE_METHOD_tcp_info_#{field}=" \
	     "#{Shellwords.shellescape(
                %Q[rb_define_method(cTCP_Info,#{rbmethod},#{cfunc},0)])}"
  end
  tcp_state_map = {
    ESTABLISHED: %w(TCP_ESTABLISHED TCPS_ESTABLISHED),
    SYN_SENT: %w(TCP_SYN_SENT TCPS_SYN_SENT),
    SYN_RECV: %w(TCP_SYN_RECV TCPS_SYN_RECEIVED),
    FIN_WAIT1: %w(TCP_FIN_WAIT1 TCPS_FIN_WAIT_1),
    FIN_WAIT2: %w(TCP_FIN_WAIT2 TCPS_FIN_WAIT_2),
    TIME_WAIT: %w(TCP_TIME_WAIT TCPS_TIME_WAIT),
    CLOSE: %w(TCP_CLOSE TCPS_CLOSED),
    CLOSE_WAIT: %w(TCP_CLOSE_WAIT TCPS_CLOSE_WAIT),
    LAST_ACK: %w(TCP_LAST_ACK TCPS_LAST_ACK),
    LISTEN: %w(TCP_LISTEN TCPS_LISTEN),
    CLOSING: %w(TCP_CLOSING TCPS_CLOSING),
  }
  nstate = 0
  tcp_state_map.each do |state, try|
    try.each do |os_name|
      have_const(os_name, headers) or next
      tcp_state_map[state] = os_name
      nstate += 1
    end
  end
  if nstate == tcp_state_map.size
    $defs << '-DRAINDROPS_TCP_STATES_ALL_KNOWN=1'
    tcp_state_map.each do |state, name|
      $defs << "-DRAINDROPS_TCP_#{state}=#{name}"
    end
  end
end

have_func("getpagesize", "unistd.h")
have_func('rb_thread_io_blocking_region')

# Both rb_thread_io_blocking_region and rb_thread_io_blocking_call are
# private Ruby APIs (not in public headers), so we forward-declare them
# in the C code. The signature changed in Ruby 4.0:
#   3.4: rb_thread_io_blocking_region(fn, data, fd)     — takes int fd
#   4.0: rb_thread_io_blocking_call(fptr, fn, data, events) — takes rb_io_t*
# Since these are private, have_func/try_compile can't reliably distinguish
# them, so we use version detection.
if RUBY_VERSION >= '4.0'
  $defs.push("-DHAVE_RB_THREAD_IO_BLOCKING_CALL")
end

checking_for "GCC atomic builtins" do
  src = <<SRC
int main(int argc, char * const argv[]) {
        unsigned long i = 0;
        __sync_lock_test_and_set(&i, 0);
        __sync_lock_test_and_set(&i, 1);
        __sync_bool_compare_and_swap(&i, 0, 1);
        __sync_add_and_fetch(&i, argc);
        __sync_sub_and_fetch(&i, argc);
        return 0;
}
SRC

  if try_link(src)
    $defs.push(format("-DHAVE_GCC_ATOMIC_BUILTINS"))
    true
  else
    false
  end
end or abort "GCC atomic builtins are required (Ruby 3.4+ implies a modern compiler)"
create_header # generate extconf.h to avoid excessively long command-line
create_makefile('raindrops_ext')
