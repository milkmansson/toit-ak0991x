// Copyright (C) 2026 Toitware Contributors. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import io
import serial.device show Device
import serial.registers show Registers
import math show *
import log

class Ak09916:
  static I2C-ADDRESS ::= 0x0C   // Magnetometer I2C address.

  // Register Map for AK09916
  static REG-COMPANY-ID_    ::= 0x00  // R 1 Device ID.
  static REG-DEV-ID_    ::= 0x01  // R 1 Device ID.
  static REG-STATUS-1_  ::= 0x10  // R 1 Data status.
  static REG-X-AXIS_    ::= 0x11  // R 2 X Axis LSB (MSB 0x12).  Signed int.
  static REG-Y-AXIS_    ::= 0x13  // R 2 Y Axis LSB (MSB 0x14).  Signed int.
  static REG-Z-AXIS_    ::= 0x15  // R 2 Y Axis LSB (MSB 0x16).  Signed int.
  static REG-TMPS_      ::= 0x17  // R 1 Temperature (AK09912 only)
  static REG-STATUS-2_  ::= 0x18  // R 1 Data status.
  static REG-CONTROL-1_ ::= 0x30  // R 1 Control Settings.
  static REG-CONTROL-2_ ::= 0x31  // R 1 Control Settings.
  static REG-CONTROL-3_ ::= 0x32  // R 1 Control Settings.

  static STATUS-1-DOR_    ::= 0b00000010 // Data Overrun.
  static STATUS-1-DRDY_   ::= 0b00000001 // New data is ready.
  static STATUS-2-HOFL_   ::= 0b00001000 // Hardware Overflow.
  static STATUS-2-RSV28_  ::= 0b00010000 // Reserved for AKM.
  static STATUS-2-RSV29_  ::= 0b00100000 // Reserved for AKM.
  static STATUS-2-RSV30_  ::= 0b01000000 // Reserved for AKM.

  // REG-CONTROL-1_ masks:  (AK09912 only)
  static CONTROL-1-TEMP-EN_ ::= 0b10000000
  static CONTROL-1-NSF_     ::= 0b01100000

  static NSF-DISABLE ::= 0b00
  static NSF-LOW ::= 0b01
  static NSF-MED ::= 0b10
  static NSF-HI  ::= 0b11


  // REG-CONTROL-2_ values:
  static OPMODE-SELF-TEST        ::= 0b00010000 // Self Test Mode.
  static OPMODE-CONT-MODE5-5HZ   ::= 0b00001110 // Continuous Mode 5.
  static OPMODE-CONT-MODE4-100HZ ::= 0b00001000 // Continuous Mode 4.
  static OPMODE-CONT-MODE3-50HZ  ::= 0b00000110 // Continuous Mode 3.
  static OPMODE-CONT-MODE2-20HZ  ::= 0b00000100 // Continuous Mode 2.
  static OPMODE-CONT-MODE1-10HZ  ::= 0b00000010 // Continuous Mode 1.
  static OPMODE-SINGLE-MODE0     ::= 0b00000001 // Single Measurement Mode.
  static OPMODE-OFF              ::= 0b00000000 // Power down mode.

  static OPMODES_ := {
    OPMODE-SELF-TEST: "OPMODE-SELF-TEST",
    OPMODE-CONT-MODE5-5HZ: "OPMODE-CONT-MODE5-5HZ",
    OPMODE-CONT-MODE4-100HZ: "OPMODE-CONT-MODE4-100HZ",
    OPMODE-CONT-MODE3-50HZ: "OPMODE-CONT-MODE3-50HZ",
    OPMODE-CONT-MODE2-20HZ: "OPMODE-CONT-MODE2-20HZ",
    OPMODE-CONT-MODE1-10HZ: "OPMODE-CONT-MODE1-10HZ",
    OPMODE-SINGLE-MODE0: "OPMODE-SINGLE-MODE0",
    OPMODE-OFF: "OPMODE-OFF"}

  static CONTROL-3-SRST_  ::= 0b00000001 // Software Reset.

  static MANUFACTURER-ID_ ::= 0x48
  static DEV-ID-AK09918 := 0x0C
  static DEV-ID-AK09912 := 0x04
  static DEV-ID-AK09916 := 0x09
  static DEV-ID-AK09911 := 0x05
  static DEV-IDS_ ::= {
    DEV-ID-AK09911: "AK09911",
    DEV-ID-AK09912: "AK09912",
    DEV-ID-AK09916: "AK09916",
    DEV-ID-AK09918: "AK09918"}

  // LSB for the specific devices
  static UT-PER-LSBS_ ::= {
    DEV-ID-AK09911: 0.15,
    DEV-ID-AK09912: 0.15,
    DEV-ID-AK09916: 0.15,
    DEV-ID-AK09918: 0.6}

  // Which devices have a $REG-TEMPS_ register
  static HAS-TEMPS_ ::= {
    DEV-ID-AK09912,
  }

  // $write-register_ statics for bit width.  All 16 bit read/writes are LE.
  static WIDTH-8_ ::= 8
  static WIDTH-16_ ::= 16
  static DEFAULT-REGISTER-WIDTH_ ::= WIDTH-8_

  reg_/Registers := ?
  logger_/log.Logger := ?
  hw-id_/int := 0
  man-id_/int := 0
  rpe_/Roll-Pitch-Estimator_ := ?

  constructor dev/Device --logger/log.Logger=log.default:
    reg_ = dev.registers
    logger_ = logger.with-name "ak09916"
    rpe_ = Roll-Pitch-Estimator_

    hw-id_ = get-hardware-id
    man-id_ = get-manufacturer-id
    if (man-id_ != MANUFACTURER-ID_) or (not DEV-IDS_.contains hw-id_):
      logger_.error "device id unrecognised" --tags={"detected": "0x$(%02x hw-id_)"}
      throw "device-id $hw-id_ unrecognised"

  get-manufacturer-id -> int:
    return read-register_ REG-COMPANY-ID_

  get-hardware-id -> int:
    return read-register_ REG-DEV-ID_

  set-operating-mode mode/int -> none:
    assert: OPMODES_.contains mode
    old-mode := read-register_ REG-CONTROL-2_
    write-register_ REG-CONTROL-2_ mode
    logger_.debug "mode switched" --tags={"was":OPMODES_[old-mode], "now":OPMODES_[mode]}

  is-data-ready -> bool:
    return (read-register_ REG-STATUS-1_ --mask=STATUS-1-DRDY_) == 1

  is-data-overrun -> bool:
    return (read-register_ REG-STATUS-1_ --mask=STATUS-1-DOR_) == 1

  is-hardware-overflow -> bool:
    return (read-register_ REG-STATUS-2_ --mask=STATUS-2-HOFL_) == 1

  read-magnetic-field -> Point3f:
    bytes := reg_.read-bytes REG-X-AXIS_ 6
    x := (io.LITTLE-ENDIAN.int16 bytes 0).to-float * UT-PER-LSBS_[hw-id_]
    y := (io.LITTLE-ENDIAN.int16 bytes 2).to-float * UT-PER-LSBS_[hw-id_]
    z := (io.LITTLE-ENDIAN.int16 bytes 4).to-float * UT-PER-LSBS_[hw-id_]

    // Read $REG-STATUS-2_ to complete the measurement cycle / clear status.
    status-2 := read-register_ REG-STATUS-2_
    if (status-2 & STATUS-2-HOFL_) != 0:
      logger_.warn "mag overflow" --tags={"status-2":"0x$(%02x status-2)"}

    return Point3f x y z

  read-bearing -> float
      field/Point3f=read-magnetic-field
      --roll/float?=null
      --pitch/float?=null
      --declination/float=0.0:
    heading/float := ?

    if (roll != null) and (pitch != null):
      if not is-finite_ roll or not is-finite_ pitch:
        logger_.error "roll or pitch are invalid"
        throw "roll or pitch are invalid"

      // Roll/Pitch (tilt compensation) given.
      cr := cos roll
      sr := sin roll
      cp := cos pitch
      sp := sin pitch
      mx2 := field.x * cp + field.z * sp
      my2 := field.x * sr * sp + field.y * cr - field.z * sr * cp
      heading = (atan2 (-1 * my2) mx2) * 180.0 / PI
    else:
      // Roll/Pitch (tilt compensation) not given.
      heading = (atan2 field.y field.x) * 180.0 / PI

    heading += declination
    if heading < 0:
      heading += 360.0
    return heading

  read-bearing -> float
      field/Point3f=read-magnetic-field
      --accel/Point3f
      --gyro/Point3f
      --declination/float=0.0:

    rpe_.update --accel=accel --gyro=gyro
    return read-bearing field --roll=rpe_.roll --pitch=rpe_.pitch --declination=declination

  // Temperature Function (Specific devices only)

  read-temperature -> float:
    if not HAS-TEMPS_.contains hw-id_:
      logger_.error "device does not have temperature register" --tags={"hw":DEV-IDS_[hw-id_]}
      return 0.0
    raw := read-register_ REG-STATUS-1_
    return 35.0 + ((120.0 - raw.to-float) / 1.6)

  enable-temperature -> none:
    if not HAS-TEMPS_.contains hw-id_:
      logger_.error "device does not have temperature register" --tags={"hw":DEV-IDS_[hw-id_]}
      return
    write-register_ REG-CONTROL-1_ 1 --mask=CONTROL-1-TEMP-EN_

  disable-temperature -> none:
    if not HAS-TEMPS_.contains hw-id_:
      logger_.error "device does not have temperature register" --tags={"hw":DEV-IDS_[hw-id_]}
      return
    write-register_ REG-CONTROL-1_ 0 --mask=CONTROL-1-TEMP-EN_

  is-temperature-enabled -> bool:
    if not HAS-TEMPS_.contains hw-id_:
      logger_.error "device does not have temperature register" --tags={"hw":DEV-IDS_[hw-id_]}
      return false
    return (read-register_ REG-CONTROL-1_ --mask=CONTROL-1-TEMP-EN_) == 1

  is-finite_ x/float? -> bool:
    if x == null: return false
    return not (x != x) and
        x != float.INFINITY and
        x != -float.INFINITY

  /**
  Reads and optionally masks/parses register data. (Little-endian.)
  */
  read-register_
      register/int
      --mask/int?=null
      --offset/int?=null
      --width/int=DEFAULT-REGISTER-WIDTH_
      --signed/bool=false -> any:
    assert: (width == 8) or (width == 16)
    raw/ByteArray := #[]

    if mask == null:
      if width == 8: mask = 0xFF
      else: mask = 0xFFFF
    if offset == null:
      offset = mask.count-trailing-zeros

    register-value/int? := null
    if width == 8:
      if signed:
        register-value = reg_.read-i8 register
      else:
        register-value = reg_.read-u8 register
    else:
      if signed:
        register-value = reg_.read-i16-le register
      else:
        register-value = reg_.read-u16-le register

    if register-value == null:
      logger_.error "read-register_ failed" --tags={"register":register}
      throw "read-register_ failed."

    if ((mask == 0xFFFF) or (mask == 0xFF)) and (offset == 0):
      return register-value
    else:
      masked-value := (register-value & mask) >> offset
      return masked-value

  /**
  Writes register data - either masked or full register writes. (Little-endian.)
  */
  write-register_
      register/int
      value/int
      --mask/int?=null
      --offset/int?=null
      --width/int=DEFAULT-REGISTER-WIDTH_
      --signed/bool=false -> none:
    assert: (width == 8) or (width == 16)
    if mask == null:
      if width == 8: mask = 0xFF
      else: mask = 0xFFFF
    if offset == null:
      offset = mask.count-trailing-zeros

    field-mask/int := (mask >> offset)
    assert: ((value & ~field-mask) == 0)  // fit check

    // Full-width direct write
    if ((width == 8)  and (mask == 0xFF)  and (offset == 0)) or
      ((width == 16) and (mask == 0xFFFF) and (offset == 0)):
      if width == 8:
        signed ? reg_.write-i8 register (value & 0xFF) : reg_.write-u8 register (value & 0xFF)
      else:
        signed ? reg_.write-i16-le register (value & 0xFFFF) : reg_.write-u16-le register (value & 0xFFFF)
      return

    // Read Reg for modification
    old-value/int? := null
    if width == 8:
      if signed :
        old-value = reg_.read-i8 register
      else:
        old-value = reg_.read-u8 register
    else:
      if signed :
        old-value = reg_.read-i16-le register
      else:
        old-value = reg_.read-u16-le register

    if old-value == null:
      logger_.error "write-register_ read existing value (for modification) failed" --tags={"register":register}
      throw "write-register_ read failed"

    new-value/int := (old-value & ~mask) | ((value & field-mask) << offset)
    if width == 8:
      signed ? reg_.write-i8 register new-value : reg_.write-u8 register new-value
      return
    else:
      signed ? reg_.write-i16-le register new-value : reg_.write-u16-le register new-value
      return
    throw "write-register_: Unhandled Circumstance."

class Roll-Pitch-Estimator_:
  alpha_/float := ?
  last-us := 0
  roll_/float := 0.0
  pitch_/float := 0.0
  logger_/log.Logger := ?

  constructor
      --accel/Point3f?=null
      --gyro/Point3f?=null
      --alpha/float=0.98
      --logger/log.Logger=log.default:
    logger_ = logger.with-name "rpe"
    alpha_ = alpha
    last-us = Time.monotonic-us

    if accel and gyro:
      update --accel=accel --gyro=gyro

  update --accel/Point3f --gyro/Point3f -> none:
    // Time step
    now := Time.monotonic-us
    dt := (now - last-us) / 1000000.0
    last-us = Time.monotonic-us

    ax := accel.x
    ay := accel.y
    az := accel.z

    // Accelerometer tilt (radians)
    roll-acc  := atan2 ay az
    pitch-acc := atan2 (-ax) (sqrt (ay * ay + az * az))

    // Gyro integration (deg/s to rad/s)
    gx := gyro.x * PI / 180.0
    gy := gyro.y * PI / 180.0

    roll-gyro  := roll  + gx * dt
    pitch-gyro := pitch + gy * dt

    if not is-finite_ roll-acc or not is-finite_ pitch-acc:
      logger_.error "roll (accel) or pitch (accel) invalid (not updating)"
      return

    if not is-finite_ roll-gyro or not is-finite_ pitch-gyro:
      logger_.error "roll (accel) or pitch (accel) invalid (not updating)"
      return

    // Complementary filter
    roll_  = alpha_ * roll-gyro  + (1.0 - alpha_) * roll-acc
    pitch_ = alpha_ * pitch-gyro + (1.0 - alpha_) * pitch-acc

  roll -> float: return roll_

  pitch -> float: return pitch_

  is-nan_ x/float -> bool:
    return x != x

  is-inf_ x/float -> bool:
    return x == float.INFINITY or x == -float.INFINITY

  is-finite_ x/float -> bool:
    if x == null: return false
    return not (is-nan_ x) and not (is-inf_ x)
