#!/usr/bin/env python3
"""Lightweight zero-dependency Sigenergy Modbus TCP poller for Omarchy."""

import json
import socket
import struct
import sys
import time


class ModbusClient:
    def __init__(self, host: str, port: int, timeout: float = 2.5):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(timeout)
        self.tx_id = 0

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def _recv_exact(self, n: int) -> bytes:
        buf = bytearray()
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("Connection closed by peer")
            buf.extend(chunk)
        return bytes(buf)

    def read_input_registers(self, unit_id: int, start_addr: int, count: int):
        self.tx_id = (self.tx_id + 1) & 0xFFFF
        req = struct.pack(">HHHBBHH", self.tx_id, 0, 6, unit_id, 4, start_addr, count)
        self.sock.sendall(req)
        hdr = self._recv_exact(9)
        _, _, _, _, fc, byte_count = struct.unpack(">HHHBBB", hdr)
        if fc & 0x80:
            return None
        data = self._recv_exact(byte_count)
        return struct.unpack(f">{len(data) // 2}H", data)


def u32(regs, offset: int) -> int:
    return (regs[offset] << 16) | regs[offset + 1]


def s32(regs, offset: int) -> int:
    v = (regs[offset] << 16) | regs[offset + 1]
    return v - 0x100000000 if v >= 0x80000000 else v


def s16(regs, offset: int) -> int:
    v = regs[offset]
    return v - 0x10000 if v >= 0x8000 else v


EMS_MODES = {
    0: "Self-Use",
    1: "Sigen AI",
    2: "TOU",
    5: "Full Feed-in",
    7: "Remote EMS",
    9: "Custom",
}

GRID_STATES = {
    0: "On-Grid",
    1: "Off-Grid (Auto)",
    2: "Off-Grid (Manual)",
}

RUN_STATES = {
    0: "Standby",
    1: "Normal",
    2: "Fault",
    3: "Power-Off",
}


def poll(host: str, port: int) -> dict:
    client = ModbusClient(host, port)
    try:
        plant = client.read_input_registers(247, 30000, 52)
        if not plant or len(plant) < 52:
            return {"ok": False, "error": "Invalid plant telemetry response"}

        daily_load_regs = client.read_input_registers(247, 30092, 2)
        daily_pv_regs = client.read_input_registers(247, 30272, 4)
        inv_energy = client.read_input_registers(1, 30554, 25)
        inv_batt = client.read_input_registers(1, 30601, 9)

        ems_mode_code = plant[3]
        grid_power_w = s32(plant, 5)        # >0 import, <0 export
        on_off_grid_code = plant[9]
        soc_pct = round(plant[14] / 10.0, 1)
        plant_alarms = list(plant[27:31])
        plant_active_w = s32(plant, 31)     # Inverter AC output to home/grid
        pv_power_w = max(0, s32(plant, 35))
        ess_power_w = s32(plant, 37)        # >0 charging, <0 discharging
        run_state_code = plant[51]

        home_load_w = max(0, plant_active_w + grid_power_w)

        daily_load_kwh = round(u32(daily_load_regs, 0) / 100.0, 2) if daily_load_regs else None
        daily_pv_kwh = round(u32(daily_pv_regs, 0) / 100.0, 2) if daily_pv_regs else None
        prev_pv_kwh = round(u32(daily_pv_regs, 2) / 100.0, 2) if daily_pv_regs else None

        daily_ac_export_kwh = round(u32(inv_energy, 0) / 100.0, 2) if inv_energy else None
        daily_ac_import_kwh = round(u32(inv_energy, 6) / 100.0, 2) if inv_energy else None
        daily_charge_kwh = round(u32(inv_energy, 12) / 100.0, 2) if inv_energy else None
        daily_discharge_kwh = round(u32(inv_energy, 18) / 100.0, 2) if inv_energy else None

        net_export_kwh = None
        if (
            daily_ac_export_kwh is not None
            and daily_ac_import_kwh is not None
            and daily_load_kwh is not None
        ):
            net_export_kwh = round((daily_ac_export_kwh - daily_ac_import_kwh) - daily_load_kwh, 2)

        soh_pct = round(inv_batt[1] / 10.0, 1) if inv_batt else None
        cell_temp_c = round(s16(inv_batt, 2) / 10.0, 1) if inv_batt else None
        cell_voltage_v = round(inv_batt[3] / 1000.0, 3) if inv_batt else None
        inv_alarms = list(inv_batt[4:9]) if inv_batt else []
        has_alarms = any(a != 0 for a in plant_alarms + inv_alarms)

        return {
            "ok": True,
            "timestamp": int(time.time()),
            "emsMode": EMS_MODES.get(ems_mode_code, f"Mode {ems_mode_code}"),
            "gridState": GRID_STATES.get(on_off_grid_code, "Unknown"),
            "runState": RUN_STATES.get(run_state_code, f"State {run_state_code}"),
            "hasAlarms": has_alarms,
            "socPct": soc_pct,
            "sohPct": soh_pct,
            "cellTempC": cell_temp_c,
            "cellVoltageV": cell_voltage_v,
            "pvPowerW": pv_power_w,
            "homeLoadW": home_load_w,
            "gridPowerW": grid_power_w,
            "essPowerW": ess_power_w,
            "plantActiveW": plant_active_w,
            "dailyPvKwh": daily_pv_kwh,
            "prevPvKwh": prev_pv_kwh,
            "dailyLoadKwh": daily_load_kwh,
            "dailyChargeKwh": daily_charge_kwh,
            "dailyDischargeKwh": daily_discharge_kwh,
            "netExportKwh": net_export_kwh,
        }
    finally:
        client.close()


def main():
    host = sys.argv[1].strip() if len(sys.argv) > 1 else ""
    if not host:
        sys.stdout.write(json.dumps({"ok": False, "error": "Host IP not configured"}) + "\n")
        return

    try:
        port = int(sys.argv[2]) if len(sys.argv) > 2 else 502
    except ValueError:
        port = 502

    try:
        result = poll(host, port)
    except Exception as exc:
        result = {"ok": False, "error": str(exc)}

    sys.stdout.write(json.dumps(result) + "\n")


if __name__ == "__main__":
    main()
