"""
TF Luna UART Distance Sensor Driver
Provides real-time distance measurements from TF Luna LiDAR sensor
"""

import serial
import time


class TFLunaDriver:
    """Interface for TF Luna distance sensor over UART"""
    
    def __init__(self, port="/dev/ttyAMA0", baudrate=115200, timeout=0.08):
        """
        Initialize TF Luna sensor connection
        
        Args:
            port: Serial port (typically /dev/ttyAMA0 for Raspberry Pi UART0)
            baudrate: UART baud rate (TF Luna default: 115200)
            timeout: Serial read timeout in seconds
        """
        try:
            self.ser = serial.Serial(port, baudrate, timeout=timeout)
            self.port = port
            self.distance_mm = 0
            self.signal_strength = 0
            self.temperature = 0
            self.connected = True
            print(f"TF Luna connected on {port} @ {baudrate} baud")
        except Exception as e:
            print(f"TF Luna failed to open {port}: {e}")
            self.ser = None
            self.connected = False
    
    def read_distance(self):
        """
        Read distance from TF Luna in millimeters
        
        TF Luna frame format:
        [0x59] [0x59] [dist_low] [dist_high] [strength_low] [strength_high] [temp_low] [temp_high] [checksum]
        Total: 9 bytes
        
        Returns:
            Distance in mm (int) or None if read failed
        """
        if not self.ser or not self.ser.is_open:
            return None
        
        try:
            deadline = time.time() + 0.30
            frame = bytearray()

            while time.time() < deadline:
                byte = self.ser.read(1)
                if not byte:
                    continue

                value = byte[0]
                if not frame:
                    if value == 0x59:
                        frame.append(value)
                    continue

                if len(frame) == 1:
                    if value == 0x59:
                        frame.append(value)
                    else:
                        frame.clear()
                    continue

                frame.append(value)
                if len(frame) < 9:
                    continue

                checksum = sum(frame[:8]) & 0xFF
                if checksum != frame[8]:
                    frame.clear()
                    continue

                self.distance_mm = frame[2] | (frame[3] << 8)
                self.signal_strength = frame[4] | (frame[5] << 8)
                temp_raw = frame[6] | (frame[7] << 8)

                if temp_raw > 32767:
                    self.temperature = (temp_raw - 65536) / 8.0
                else:
                    self.temperature = temp_raw / 8.0

                return self.distance_mm
            
            return None
        except Exception as e:
            print(f"TF Luna read error: {e}")
            return None
    
    def get_status(self):
        """Get current sensor status"""
        return {
            "connected": self.ser.is_open if self.ser else False,
            "port": self.port,
            "distance_mm": self.distance_mm,
            "signal_strength": self.signal_strength,
            "temperature_c": round(self.temperature, 1)
        }
    
    def close(self):
        """Close serial connection"""
        if self.ser and self.ser.is_open:
            self.ser.close()
            self.connected = False
            print("TF Luna closed")
