#!/usr/bin/env ruby

require "evdev"
require "open3"

device = Evdev.new('/dev/input/event3')
cmd = ""

all_keys = *('A'..'Z').map { |l| :"KEY_#{l}"}
device.on(*all_keys) do |state, key|
  if state == 1
    cmd += key.to_s[-1].downcase
  end
end

device.on(:KEY_ENTER) do |state, key|
  unless cmd.empty?
    # execute command
    Open3.capture3(cmd)
    cmd = ""
  end
end

# # blocks the device for other applications
# puts device.grab

loop do
  begin
    device.handle_event
  rescue Evdev::AwaitEvent
    Kernel.select([device.event_channel])
    retry
  end
end
