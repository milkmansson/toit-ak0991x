# Toit driver for AK0991x (AK09916 and sibling) magnetometer/compass devices.

A very basis Toit driver for AK09916 (and sibling I2C devices) from Asahi Kasei.

## Usage
This driver can be used as with any other I2C device.  To directly access the
AK09916 built into an ICM20948 device on the I2C bus, the ICM20948 must be first
be placed into `i2c-bypass` mode.

### Example
```Toit
import gpio
import i2c
import ak0991x

main:
  bus := i2c.Bus
    --sda=gpio.Pin 8
    --scl=gpio.Pin 9
    --frequency=400_000

  if not (bus.test icm20948.Driver.AK09916-I2C-ADDRESS):
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

 ```
