// Copyright (C) 2026 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ak0991x

main:
  bus := i2c.Bus
    --sda=gpio.Pin 8
    --scl=gpio.Pin 9
    --frequency=400_000

  if not (bus.test ak0991x.Ak0991x.I2C-ADDRESS):
    print "bus missing the device. stopping..."
    return

  ak-device := bus.device ak0991x.Ak0991x.I2C-ADDRESS
  ak-sensor := ak0991x.Ak0991x ak-device

  print "Bus contains AK09916."
  print "Hardware ID: 0x$(%02x ak-sensor.get-hardware-id)"
  ak-sensor.set-operating-mode ak0991x.Ak0991x.OPMODE-CONT-MODE1-10HZ
  sleep --ms=250
  print "Data Ready: $(ak-sensor.is-data-ready)"
  print "Magnetic Field: $ak-sensor.read-magnetic-field"
  print "Bearing (no compensation)  : $(%0.3f ak-sensor.read-bearing)"
