# frozen_string_literal: true

require "test_helper"

class TestGVLTiming < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::GVLTiming::VERSION
  end

  def test_timing_idle_sleep
    timer = GVLTiming::Timer.new
    timer.start
    sleep 0.1
    timer.stop

    assert_in_delta 100000000, timer.duration_ns, 5000000
    assert_in_delta 100000000, timer.idle_duration_ns, 5000000
    assert_in_delta 0, timer.cpu_duration_ns, 5000000
    assert_in_delta 0, timer.stalled_duration_ns, 5000000
    assert_in_delta 0, timer.running_duration_ns, 5000000
    assert_operator 0, :<, timer.releases_count
  end

  def test_timing_busy_sleep
    timer = GVLTiming::Timer.new
    timer.start
    target = Process::clock_gettime(Process::CLOCK_MONOTONIC) + 0.1
    while Process::clock_gettime(Process::CLOCK_MONOTONIC) < target
      # busy
    end
    timer.stop

    assert_in_delta 100000000, timer.duration_ns, 5000000
    assert_in_delta 100000000, timer.running_duration_ns, 5000000
    #assert_in_delta 100000000, timer.cpu_duration_ns, 10000000
    assert_in_delta 0, timer.stalled_duration_ns, 5000000
    assert_in_delta 0, timer.idle_duration_ns, 5000000
  end

  def test_timing_stalled_sleep
    done = false
    wait = Mutex.new
    wait.lock
    thread = Thread.new do
      wait.lock
      target = Process::clock_gettime(Process::CLOCK_MONOTONIC) + 0.1
      while Process::clock_gettime(Process::CLOCK_MONOTONIC) < target
        # busy
      end
      done = true
    end

    timer = GVLTiming::Timer.new
    timer.start
    wait.unlock
    until done
      Thread.pass
    end
    timer.stop

    assert_in_delta 100000000, timer.duration_ns, 5000000
    assert_in_delta 100000000, timer.stalled_duration_ns, 5000000
    assert_in_delta 0, timer.cpu_duration_ns, 5000000
    assert_in_delta 0, timer.running_duration_ns, 5000000
    assert_in_delta 0, timer.idle_duration_ns, 5000000
  ensure
    thread&.kill
  end

  def test_timing_units
    timer = GVLTiming.measure { sleep 0.1 }

    assert_in_delta 100000000, timer.duration_ns, 5000000
    assert_in_delta 0.1, timer.duration, 0.005
    assert_in_delta 0.1, timer.duration(:float_second), 0.005
    assert_in_delta 100, timer.duration(:float_millisecond), 5
    assert_in_delta 100_000, timer.duration(:float_microsecond), 5000

    assert_equal 0, timer.duration(:second)
    assert_in_delta 100, timer.duration(:millisecond), 5
    assert_in_delta 100_000, timer.duration(:microsecond), 5_000
    assert_in_delta 100_000_000, timer.duration(:nanosecond), 5_000_000
  end

  def test_measure_and_inspect
    timer = GVLTiming.measure { sleep 0.1 }
    expected = "#<GVLTiming::Timer total=0.10s running=0.00s idle=0.10s stalled=0.00s yields=1>"
    assert_equal expected, timer.inspect
  end

  def test_current_state
    timer = GVLTiming::Timer.new
    timer.start

    idle_thread = Thread.new do
      sleep 0.05
      timer.current_state
    end

    sleep 0.1

    state_while_sleeping = idle_thread.join.value

    assert_equal :idle, state_while_sleeping
    assert_equal :running, timer.current_state
  ensure
    timer.stop
  end

  def test_monotonic_state_changed_ns
    timer = GVLTiming::Timer.new
    timer.start

    initial_state_changed = timer.monotonic_state_changed_ns

    sleep 0.1

    last_state_changed = timer.monotonic_state_changed_ns

    assert_in_delta 100_000_000, (last_state_changed - initial_state_changed), 5_000_000
  ensure
    timer.stop
  end

  def test_running
    timer = GVLTiming::Timer.new
    timer.start

    assert timer.active?, "timer not active"

    timer.stop

    assert !timer.active?, "timer still active"
  end
end
