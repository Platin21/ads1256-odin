package ads1256

import "../bcm2835"

import "core:fmt"

RST_PIN  :: 18
CS_PIN   :: 22
DRDY_PIN :: 17

CMD :: enum u8
{
	CMD_WAKEUP  = 0x00,	// Completes SYNC and Exits Standby Mode 0000  0000 (00h)
	CMD_RDATA   = 0x01, // Read Data 0000  0001 (01h)
	CMD_RDATAC  = 0x03, // Read Data Continuously 0000   0011 (03h)
	CMD_SDATAC  = 0x0F, // Stop Read Data Continuously 0000   1111 (0Fh)
	CMD_RREG    = 0x10, // Read from REG rrr 0001 rrrr (1xh)
	CMD_WREG    = 0x50, // Write to REG rrr 0101 rrrr (5xh)
	CMD_SELFCAL = 0xF0, // Offset and Gain Self-Calibration 1111    0000 (F0h)
	CMD_SELFOCAL= 0xF1, // Offset Self-Calibration 1111    0001 (F1h)
	CMD_SELFGCAL= 0xF2, // Gain Self-Calibration 1111    0010 (F2h)
	CMD_SYSOCAL = 0xF3, // System Offset Calibration 1111   0011 (F3h)
	CMD_SYSGCAL = 0xF4, // System Gain Calibration 1111    0100 (F4h)
	CMD_SYNC    = 0xFC, // Synchronize the A/D Conversion 1111   1100 (FCh)
	CMD_STANDBY = 0xFD, // Begin Standby Mode 1111   1101 (FDh)
	CMD_RESET   = 0xFE, // Reset to Power-Up Values 1111   1110 (FEh)
}

V_REF :: enum {
	V5,
	V3,
	V3_3,
	V3_295,
}

DATA_RATE :: enum u8 {
	r30000SPS = 0xF0,
	r15000SPS = 0xE0,
	r7500SPS  = 0xD0,
	r3750SPS  = 0xC0,
	r2000SPS  = 0xB0,
	r1000SPS  = 0xA1,
	r500SPS   = 0x92,
	r100SPS   = 0x82,
	r60SPS    = 0x72,
	r50SPS    = 0x63,
	r30SPS    = 0x53,
	r25SPS    = 0x43,
	r15SPS    = 0x33,
	r10SPS    = 0x20,
	r5SPS     = 0x13,
	r2d5SPS   = 0x03,
}

GAIN :: enum u8
{
  GAIN_1  = 0, /* GAIN  1 */
  GAIN_2  = 1, /* GAIN  2 */
  GAIN_4  = 2, /* GAIN  4 */
  GAIN_8  = 3, /* GAIN  8 */
  GAIN_16 = 4, /* GAIN 16 */
  GAIN_32 = 5, /* GAIN 32 */
  GAIN_64 = 6, /* GAIN 64 */
}

REG :: enum u8
{
	/*Register address, followed by reset the default values */
	STATUS = 0,	// x1H
	MUX    = 1, // 01H
	ADCON  = 2, // 20H
	DRATE  = 3, // F0H
	IO     = 4, // E0H
	OFC0   = 5, // xxH
	OFC1   = 6, // xxH
	OFC2   = 7, // xxH
	FSC0   = 8, // xxH
	FSC1   = 9, // xxH
	FSC2   = 10, // xxH
};

dg_read :: proc(pin: u8) -> u8 {
	return bcm2835.gpio_lev(pin)
}

dg_write :: proc(pin: u8, value: u8) {
	bcm2835.gpio_write(pin, value)
}


dg_write_reset :: proc(value: u8) {
	dg_write(RST_PIN, value)
}

dg_write_chip_sel :: proc(value: u8) {
	dg_write(CS_PIN, value)
}

dg_read_data_ready :: proc() -> u8 {
	return dg_read(DRDY_PIN)
}

write_cmd :: proc(cmd: u8) {
	dg_write_chip_sel(bcm2835.LOW)
    spi_write(cmd)
    dg_write_chip_sel(bcm2835.HIGH)
}

reset :: proc() {
	dg_write_reset(bcm2835.HIGH)
    bcm2835.delay(200)
    dg_write_reset(bcm2835.LOW)
    bcm2835.delay(200)
    dg_write_reset(bcm2835.HIGH)
}

spi_read :: proc() -> u8 {
	return bcm2835.spi_transfer(0xff);
}

spi_write :: proc(val: u8) {
	 bcm2835.spi_transfer(val)
}

wait_for_data_ready :: proc() -> bool
{
	i := 0
    for i < 4000000 {
        if dg_read_data_ready() == 0 {
            return true
        }
        i += 1
    }

    return false
}

vref_float :: proc(vref: V_REF) -> f32 {
	switch vref {
	case .V5:
		return 5.0
	case .V3:
		return 3.0
	case .V3_3:
		return 3.3
	case .V3_295:
		return 3.295
	case:
		return 3.0 // we just assume you are using 3v then..
	}
}

read_adc_data_24bit :: proc() -> u32 {
    buf: [3]u8 = {0,0,0}

    for !wait_for_data_ready() { bcm2835.delay(100) }
    dg_write_chip_sel(bcm2835.LOW);
    spi_write(u8(CMD.CMD_RDATA))
    bcm2835.delayMicroseconds(120);
    buf[0] = spi_read();
    buf[1] = spi_read();
    buf[2] = spi_read();
    dg_write_chip_sel(bcm2835.HIGH);

    read := (i32(buf[0]) << 16) +
			(i32(buf[1] << 8)) +
			 i32(buf[2]);

	return u32(read);
}

read_adc_data_signed :: proc() -> i32 {
	data: u32 = read_adc_data_24bit()
	if data & 0x00800000 != 0 {
		data |= 0xff000000;
	}

	return i32(data)
}

read_adc_data_f32 :: proc() -> f32 {
	data: i32 = read_adc_data_signed()
	return f32(data)
}

read_adc_data :: proc (vref: f32, gain: u8) -> f32 {
	adc_val: f32 = read_adc_data_f32()
	pga := f32(u8(1 << gain))
	return ((adc_val / 0x7FFFFF) * ((2 * vref) / pga));
}

get_channel_value_raw_integer :: proc(ch: u8) -> i32 {
	for wait_for_data_ready() != true {}
	set_active_channel(ch);
	spi_write(u8(CMD.CMD_SYNC))
	spi_write(u8(CMD.CMD_WAKEUP))
	return read_adc_data_signed()
}


get_channel_value_raw :: proc(ch: u8) -> f32 {
	for wait_for_data_ready() != true {}
	set_active_channel(ch);
	spi_write(u8(CMD.CMD_SYNC))
	spi_write(u8(CMD.CMD_WAKEUP))
 	adc_val := read_adc_data_f32()
	return (adc_val / 0x7FFFFF) // we don't do a conversion factor here!
}

get_channel_value :: proc(ch: u8, vref: V_REF, gain: GAIN) -> f32 {
	for wait_for_data_ready() != true {}
	set_active_channel(ch);
	spi_write(u8(CMD.CMD_SYNC))
	spi_write(u8(CMD.CMD_WAKEUP))
	return read_adc_data(vref_float(vref), u8(gain));
}

read_register :: proc(reg: REG) -> u8
{
    dg_write_chip_sel(bcm2835.LOW);
    spi_write(u8(CMD.CMD_RREG) | u8(reg));
    spi_write(0x00);
    bcm2835.delay(1);
    temp := spi_read();
    dg_write_chip_sel(bcm2835.HIGH);
    return temp;
}

write_register :: proc(register: REG, value: u8)
{
    dg_write_chip_sel(bcm2835.LOW);
    spi_write(u8(CMD.CMD_WREG) | u8(register));
    spi_write(0x00);
    spi_write(value);
    dg_write_chip_sel(bcm2835.HIGH);
}

read_chip_id :: proc() -> u8 {
	if wait_for_data_ready() {
		return read_register(.STATUS)
	}
	return 255
}

set_active_channel :: proc(ch: u8) {
	if ch < 7 {
		write_register(.MUX, (ch << 4) | (1 << 3))
	}
}

init :: proc(gain: GAIN, data_rate: DATA_RATE) -> bool {

	// configure pins
	bcm2835.gpio_fsel(RST_PIN, .GPIO_FSEL_OUTP)
    bcm2835.gpio_fsel(CS_PIN, .GPIO_FSEL_OUTP)
	bcm2835.gpio_fsel(DRDY_PIN, .GPIO_FSEL_INPT)

	bcm2835.spi_begin();
    bcm2835.spi_setBitOrder(.SPI_BIT_ORDER_MSBFIRST)
    bcm2835.spi_setDataMode(.SPI_MODE1)
   	bcm2835.spi_setClockDivider(.SPI_CLOCK_DIVIDER_128)

   	configure_adc(gain, data_rate)

   	return true
}

configure_adc :: proc(gain: GAIN, drate: DATA_RATE)
{
    wait_for_data_ready()
    buf: [4]u8 = {0,0,0,0}
    buf[0] = (0<<3) | (1<<2) | (0<<1)
    buf[1] = 0x08
    buf[2] = (0<<5) | (0<<3) | (u8(gain)<<0)
    buf[3] = u8(drate)
    dg_write_chip_sel(bcm2835.LOW)
    spi_write(u8(CMD.CMD_WREG) | 0)
    spi_write(0x03)

    spi_write(buf[0])
    spi_write(buf[1])
    spi_write(buf[2])
    spi_write(buf[3])
    dg_write_chip_sel(bcm2835.HIGH);
    bcm2835.delay(1);
}

deinit :: proc() {
	bcm2835.spi_end();
}
