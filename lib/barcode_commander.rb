# frozen_string_literal: true

require "evdev" if RUBY_PLATFORM.match?(/linux/i)
require "fileutils"
require "mono_logger"
require "open3"

class BarcodeCommander
  def initialize
    @logger = MonoLogger.new("log/barcode_commander.log", 1, 1024 ** 2 * 100)
    @logger.info ""
    @logger.info "Starting barcode commander..."
    @logger.info "Process PID #{Process.pid}"

    detect_scanner

  rescue Interrupt
    shutdown
  end

  def listen!
    # Generate alphabet
    all_keys = *("0".."Z").map { |l| :"KEY_#{l}" }
    @device.on(*all_keys) do |state, key|
      if state == 1
        @cmd += key.to_s[-1].downcase
      end
    end

    # Execute command
    @device.on(:KEY_ENTER) do |state, key|
      unless @cmd.empty?
        Open3.capture3(@cmd)
        logger.info "Barcode command: #{@cmd}"

        @cmd = ""
      end
    end

    # Blocks the device for other applications
    @device.grab

    # Main listen loop
    loop do
      begin
        @device.handle_event
      rescue Evdev::AwaitEvent
        Kernel.select([@device.event_channel])
        retry
      end
    end
  end

  private
    attr_reader :logger, :pidfile

    def detect_scanner
      # Detect barcode scanner
      xinput_device = `xinput list | grep "USB Virtual PS2 Port"`
      xinput_device =~ /\w.*id=(\d{1,3}).*/
      xinput_device_id = Regexp.last_match(1).to_i
      logger.info "Barcode reader xinput device id #{xinput_device_id}"

      device_node = `xinput list-props #{xinput_device_id} | grep 'Device Node'`
      device_node =~ /\w.*\/dev\/input\/event(\d{1,3}).*/
      device_event_id = Regexp.last_match(1).to_i
      logger.info "Barcode reader device event id #{device_event_id}"

      if xinput_device_id == 0 || device_event_id == 0
        logger.error "Exiting barcode reader wasn't found!"
        raise BarcodeNotFound
      end

      # Attach device
      @device = Evdev.new("/dev/input/event#{device_event_id}")
      @cmd = ""

      # Print device description
      logger.info "Detected barcode device"
      device_params = [:name, :phys, :uniq, :vendor_id, :product_id, :bustype, :version, :driver_version]
      device_params.each do |param|
        logger.info "#{param}: #{@device.send(param)}"
      end
    end

    def shutdown
      logger.info "Shutting down barcode commander"
      @device.ungrab
      exit(0)
    end
end

class BarcodeCommander::DeviceNotFound < StandardError
end
