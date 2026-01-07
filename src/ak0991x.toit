// Copyright (C) 2026 Toitware Contributors. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE file.

import io
import serial.device show Device
import serial.registers show Registers
import math show *
import log

class Ak0991x:
  static I2C-ADDRESS ::= 0x0C   // Magnetometer I2C address.

  // Register Map for AK09916
  static REG-COMPANY-ID_    ::= 0x00  // R 1 Device ID.
  static REG-DEV-ID_    ::= 0x01  // R 1 Device ID.
  static REG-RSV-1_     ::= 0x02  // R 1 Reserved 1.
  static REG-RSV-2_     ::= 0x03  // R 1 Reserved 2.
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
  static OPMODE-INVALID          ::= 0b11111111

  static OPMODES_ := {
    OPMODE-INVALID: "UNINITIALISED",
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
  operating-mode_/int := OPMODE-OFF
  declination_/float := 0.0
  fused-compass_/FusedCompass_ := ?

  constructor dev/Device --logger/log.Logger=log.default:
    reg_ = dev.registers
    logger_ = logger.with-name "ak09916"
    fused-compass_ = FusedCompass_ --logger=logger_

    hw-id_ = get-hardware-id
    man-id_ = get-manufacturer-id
    if (man-id_ != MANUFACTURER-ID_) or (not DEV-IDS_.contains hw-id_):
      logger_.error "device id unrecognised" --tags={"detected": "0x$(%02x hw-id_)"}
      throw "device-id $hw-id_ unrecognised"

    //Synchronise OPMODE
    set-operating-mode OPMODE-OFF

  /** Gives the manufacturer ID. */
  get-manufacturer-id -> int:
    return read-register_ REG-COMPANY-ID_

  /** Gives the device model ID. */
  get-hardware-id -> int:
    return read-register_ REG-DEV-ID_

  /**
  Sets operating (measuring) mode.

  One of $OPMODE-SELF-TEST, $OPMODE-CONT-MODE4-100HZ, $OPMODE-CONT-MODE3-50HZ,
    $OPMODE-CONT-MODE2-20HZ, $OPMODE-CONT-MODE1-10HZ, $OPMODE-SINGLE-MODE0,
    $OPMODE-OFF, or $OPMODE-CONT-MODE5-5HZ (specific models only).
  */
  set-operating-mode mode/int -> none:
    assert: (OPMODES_.contains mode) and (mode != OPMODE-INVALID)
    if operating-mode_ == mode:
      // mode change unnecessary.
      return
    write-register_ REG-CONTROL-2_ mode
    if operating-mode_ != mode: operating-mode_ = mode
    logger_.info "mode switched" --tags={"was":OPMODES_[operating-mode_], "now":OPMODES_[mode]}

  /** Whether data is ready. */
  is-data-ready -> bool:
    return (read-register_ REG-STATUS-1_ --mask=STATUS-1-DRDY_) == 1

  /** Whether data overrun has been triggered. */
  is-data-overrun -> bool:
    return (read-register_ REG-STATUS-1_ --mask=STATUS-1-DOR_) == 1

  /** Whether hardware overflow has been triggered. */
  is-hardware-overflow -> bool:
    return (read-register_ REG-STATUS-2_ --mask=STATUS-2-HOFL_) == 1


  // Reads this way to match DMP method for ICM20948.  It reads all the values
  // for a single measurement at once, including REG-STATUS-2_, which clears
  // the $STATUS-1-DRDY_ bit.
  read-magnetic-field -> Point3f:
    if operating-mode_ == OPMODE-OFF:
      // Cope with one shot mode.  Set to single shot, then do measurement.
      // Single shot returns mode to $OPMODE-OFF afterwards.
      set-operating-mode OPMODE-SINGLE-MODE0
    bytes := reg_.read-bytes REG-RSV-2_ 10
    x := (io.LITTLE-ENDIAN.int16 bytes 2).to-float * UT-PER-LSBS_[hw-id_]
    y := (io.LITTLE-ENDIAN.int16 bytes 4).to-float * UT-PER-LSBS_[hw-id_]
    z := (io.LITTLE-ENDIAN.int16 bytes 6).to-float * UT-PER-LSBS_[hw-id_]

    // Reading $REG-STATUS-2_ (in bytes[9]) resets $STATUS-1-DRDY_.
    // Checking $REG-STATUS-2_ for Hardware Overflow ($STATUS-2-HOFL_).
    if (bytes[9] & STATUS-2-HOFL_) != 0:
      logger_.warn "mag overflow" --tags={"status-2":"0x$(%02x bytes[9])"}

    return Point3f x y z

  /** Converts a read-magnetic-field point3f into a bearing. */
  read-bearing field/Point3f=read-magnetic-field -> float:
    heading/float := ?
    heading = (atan2 field.y field.x) * 180.0 / PI
    heading += declination_
    if heading < 0:
      heading += 360.0
    return heading

  /**
  Converts a read-magnetic-field point3f into a tilt corrected bearing.

  Requires Gyro/Accelerometer data in Point3f's in $accel and $gyro.
  */
  read-bearing-fused -> float
      --mag/Point3f=read-magnetic-field
      --accel/Point3f
      --gyro/Point3f:
    return fused-compass_.update --accel=accel --gyro=gyro --mag=mag

  /**
  Set the declination of the current location.

  Compass declination (also called magnetic declination) is the angle between
    true north (the direction toward Earth's geographic North Pole) and magnetic
    north (the direction a compass needle points).  Because Earth's magnetic
    field shifts over time and varies by location, this angle differs depending
    on where you are and must be accounted for when navigating with a map and
    compass.

  This is set once on the class, and will only affect subsequent bearing reads.
  */
  set-declination --degrees/float -> none:
    declination_ = degrees
    fused-compass_.set-declination --degrees=degrees

  // Temperature Function (Specific devices only)

  /** Reads current die temperature (if available). */
  read-temperature -> float:
    if not HAS-TEMPS_.contains hw-id_:
      logger_.error "device does not have temperature register" --tags={"hw":DEV-IDS_[hw-id_]}
      return 0.0
    raw := read-register_ REG-STATUS-1_
    return 35.0 + ((120.0 - raw.to-float) / 1.6)

  /** Enables temperature reading (if available). */
  enable-temperature -> none:
    if not HAS-TEMPS_.contains hw-id_:
      logger_.error "device does not have temperature register" --tags={"hw":DEV-IDS_[hw-id_]}
      return
    write-register_ REG-CONTROL-1_ 1 --mask=CONTROL-1-TEMP-EN_

  /** Disables temperature reading (if available). */
  disable-temperature -> none:
    if not HAS-TEMPS_.contains hw-id_:
      logger_.error "device does not have temperature register" --tags={"hw":DEV-IDS_[hw-id_]}
      return
    write-register_ REG-CONTROL-1_ 0 --mask=CONTROL-1-TEMP-EN_

  /** Whether temperature reading is enabled (if available). */
  is-temperature-enabled -> bool:
    if not HAS-TEMPS_.contains hw-id_:
      logger_.error "device does not have temperature register" --tags={"hw":DEV-IDS_[hw-id_]}
      return false
    return (read-register_ REG-CONTROL-1_ --mask=CONTROL-1-TEMP-EN_) == 1

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


class FusedCompass_:
  // up_ is a unit vector pointing "up" in sensor coordinates.
  up_/Point3f := Point3f 0 0 1
  last-us_ := Time.monotonic-us
  seeded_ := false
  logger_/log.Logger := ?

  up-correction-rate_/float := 0.02
  accel-min-g_/float := 0.85
  accel-max-g_/float := 1.15
  declination-deg_/float := 0.0

  constructor
      --up-correction-rate/float=0.02
      --accel-min-g/float=0.85
      --accel-max-g/float=1.15
      --declination-deg/float=0.0
      --logger/log.Logger=log.default:
    logger_ = logger.with-name "fusedcompass"
    up-correction-rate_ = up-correction-rate
    accel-min-g_ = accel-min-g
    accel-max-g_ = accel-max-g
    declination-deg_ = declination-deg
    last-us_ = Time.monotonic-us

  // Call once to seed up_ from accel when you're roughly still.
  seed accel/Point3f -> none:
    // Up is opposite gravity
    u := unit3_ (Point3f (-accel.x) (-accel.y) (-accel.z))
    if u == null:
      seeded_ = false
      return
    up_ = u
    last-us_ = Time.monotonic-us
    seeded_ = true
    logger_.debug "measurement seeded" --tags={"u": u}

  is-seeded -> bool:
    return seeded_

  set-declination --degrees/float=0.0 -> none:
    assert: 0 <= degrees <= 360.0
    declination-deg_ = degrees
    logger_.debug "declination set" --tags={"declination": degrees}

  /**
  Configures 'up correction rate'.

  How fast accel pulls "up" back (0..1-ish). Smaller = rely more on gyro.
  */
  set-up-correction-rate rate/float=0.02 -> none:
    assert: 0 <= rate <= 1.2
    up-correction-rate_ = rate
    logger_.debug "up-correction-rate set" --tags={"rate": rate}

  /**
  Sets minimum and maximum G - gates accel correction when not near 1g.
  */
  set-accel-min-max-g --min/float?=null --max/float?=null -> none:
    if min != null:
      accel-min-g_ = min
      logger_.debug "acceleration min g set" --tags={"min": min}

    if max != null:
      accel-max-g_ = max
      logger_.debug "acceleration max g set" --tags={"min": max}

  /**
  Returns heading in degrees [0..360], or NAN if not computable this cycle.
  */
  update --accel/Point3f --gyro/Point3f --mag/Point3f -> float:
    // In case the documentation wasn't read and the accel is not already seeded.
    if not is-seeded:
      seed accel

    logger_.debug "starting gyro" --tags={"gyro":"$gyro"}
    logger_.debug "starting accel" --tags={"accel":"$accel"}
    logger_.debug "starting mag" --tags={"mag":"$mag"}
    logger_.debug "starting up" --tags={"up":"$up_"}

    now := Time.monotonic-us
    dt := (now - last-us_) / 1000000.0
    last-us_ = now
    if dt <= 0.0:
      logger_.error "NAN due to time calculation"
      return float.NAN

    // Gyro is deg/s from your driver; convert to rad/s.
    wx := gyro.x * PI / 180.0
    wy := gyro.y * PI / 180.0
    wz := gyro.z * PI / 180.0
    logger_.debug "gyro rad/s x=$wx y=$wy z=$wz"

    // 1) Propagate "up" using gyro
    up1 := rotate-small up_ wx wy wz dt
    if up1 == null:
      logger_.error "NAN due to up1 == null"
      return float.NAN
    up_ = up1
    logger_.debug "propagated up" --tags={"up":"$up_"}

    // 2) Correct "up" toward accelerometer gravity only when accel magnitude ~ 1g
    amag := norm3_ accel
    if amag >= accel-min-g_ and amag <= accel-max-g_:
      logger_.debug "accel magnitude between max and min" --tags={"amag":"$(%0.3f amag)"}
      up-acc := unit3_ (Point3f (-accel.x) (-accel.y) (-accel.z))
      if up-acc != null:
        blended := unit3_ (lerp3_ up_ up-acc up-correction-rate_)
        if blended != null:
          up_ = blended
          logger_.debug "up_ became blended" --tags={"blended":"$up_"}


    // 3) Tilt-compensate magnetometer by projecting onto horizontal plane
    // mh = mag - up*(mag·up)
    mh := sub3_ mag (mul3_ up_ (dot3_ mag up_))
    mh-u := unit3_ mh
    if mh-u == null:
      logger_.error "NAN due to mh-u == null"
      return float.NAN
    logger_.debug "mh changed" --tags={"mh":"$mh", "mh-u":"$mh-u"}

    // Heading from tilt-compensated horizontal mag vector.
    heading := (atan2 mh_u.y mh_u.x) * 180.0 / PI
    heading += declination-deg_

    while heading < 0.0: heading += 360.0
    while heading >= 360.0: heading -= 360.0
    return heading

  // Rotate vector v by small-angle gyro vector w (rad/s) over dt seconds.
  // Using first-order approximation: v' = v + (w × v) * dt
  // Then renormalize.
  rotate-small v/Point3f wx/float wy/float wz/float dt/float -> Point3f?:
    dv := mul3_ (cross3_ (Point3f wx wy wz) v) dt
    return unit3_ (add3_ v dv)

  norm3_ v/Point3f -> float:
    return sqrt (v.x*v.x + v.y*v.y + v.z*v.z)

  unit3_ v/Point3f -> Point3f?:
    n := norm3_ v
    if n < 1e-6: return null
    return Point3f (v.x/n) (v.y/n) (v.z/n)

  dot3_ a/Point3f b/Point3f -> float:
    return a.x * b.x + a.y * b.y + a.z * b.z

  cross3_ a/Point3f b/Point3f -> Point3f:
    return Point3f
      (a.y * b.z - a.z * b.y)
      (a.z * b.x - a.x * b.z)
      (a.x * b.y - a.y * b.x)

  add3_ a/Point3f b/Point3f -> Point3f:
    return  Point3f (a.x+b.x) (a.y+b.y) (a.z+b.z)

  sub3_ a/ Point3f b/Point3f -> Point3f:
    return Point3f (a.x - b.x) (a.y - b.y) (a.z - b.z)

  mul3_ v/Point3f s/float -> Point3f:
    return Point3f (v.x*s) (v.y*s) (v.z*s)

  lerp3_ a/Point3f b/Point3f t/float -> Point3f:
    return add3_ (mul3_ a (1.0 - t)) (mul3_ b t)

  is-finite x/float -> bool:
    return x == x and x != float.INFINITY and x != -float.INFINITY
