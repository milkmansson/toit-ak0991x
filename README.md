# Toit driver for AK0991x (AK09916 and sibling) magnetometer/compass devices.
A very basic Toit driver for AK09916 (and sibling I2C devices using the same
register map: AK09912, AK09915, AK09916, and AK09918) from Asahi Kasei
Microelectronics.

## Usage
This driver can be used as with any other I2C device.  To directly access the
AK09916 built into an ICM20948 device on the I2C bus, the ICM20948 must be first
be placed into `i2c-bypass` mode.

### Example
See examples in the [examples](./examples/) folder.
```Toit
import gpio
import i2c
import ak0991x

main:
  bus := i2c.Bus
    --sda=gpio.Pin 8
    --scl=gpio.Pin 9
    --frequency=400_000

  if not (bus.test ak0991x.Ak0991x.I2C-ADDRESS):
    print "bus missing the I2C address. stopping..."
    return

  ak-device := bus.device ak0991x.Ak0991x.I2C-ADDRESS
  ak-sensor := ak0991x.Ak0991x ak-device

  print "Bus contains AK09916."
  print "Hardware ID: 0x$(%02x ak-sensor.get-hardware-id)"

  // Start the sensor.  All data returned as zero without this.
  ak-sensor.set-operating-mode ak0991x.Ak0991x.OPMODE-CONT-MODE1-10HZ

  sleep --ms=250
  print "Data Ready: $(ak-sensor.is-data-ready)"
  print "Magnetic Field: $ak-sensor.read-magnetic-field"
  print "Bearing (no compensation)  : $(%0.3f ak-sensor.read-bearing)"

 ```

### Functions
Major functions Provided:
| Function | Explanation |
| - | - |
| `read-magnetic-field` | Reads raw magnetometer data, returned in a `Point3f`. |
| `read-bearing` | Turns a raw magnetometer reading into a degree bearing. No tilt compensation. |
| `read-bearing-fused` | A basic sensor fusion function, computing a bearing and taking `--accel` and `--gyro` Point3f's as inputs. Implemented using the `FusedCompass_` class.  _Further Testing required - requires a better test setup than is presently available._ |
| `set-operating-mode` | Sets the operating mode to static, or 10Hz, 20Hz, 50Hz, or 100Hz. |

## To do:
- Provide a calibration method.
- Do better documentation (currently the code function names etc are largely self-explanatory).

## Links
- [AK09912 Datasheet](https://datasheet.datasheetarchive.com/originals/dk/DKDS-11/203760.pdf)
- [AK09916 Datasheet](https://www.digikey.hk/htmldatasheets/production/2044105/0/0/1/AK09916.pdf)
- [AK09918 Datasheet](https://www.akm.com/content/dam/documents/products/electronic-compass/ak09918c/ak09918c-en-datasheet.pdf)

## Issues
If there are any issues, changes, or any other kind of feedback, please
[raise an issue](./issues). Feedback is welcome and appreciated!

## Disclaimer
- This driver has been written and tested testing the AK09916 module directly on
  an ICM20948.
- All trademarks belong to their respective owners.
- No warranties for this work, express or implied.

## Credits
- AI has been used for a good portion of the math, as well as coding reviews,
  analysing & compiling outcomes, and assisting with ensuring accuracy.
- [Florian](https://github.com/floitsch) for the support and encouragement
- The wider Toit developer team (past and present) for a truly excellent product

## About Toit
One would assume you are here because you know what Toit is.  If you dont:
> Toit is a high-level, memory-safe language, with container/VM technology built
> specifically for microcontrollers (not a desktop language port). It gives fast
> iteration (live reloads over Wi-Fi in seconds), robust serviceability, and
> performance that’s far closer to C than typical scripting options on the
> ESP32. [[link](https://toitlang.org/)]
- [Review on Soracom](https://soracom.io/blog/internet-of-microcontrollers-made-easy-with-toit-x-soracom/)
- [Review on eeJournal](https://www.eejournal.com/article/its-time-to-get-toit)
