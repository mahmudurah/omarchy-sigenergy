# Omarchy Sigenergy

A native [Omarchy](https://omarchy.org) shell bar widget and popup card for **Sigenergy** (SigenStor / Sigen Hybrid) home solar & battery systems, polled directly over local **Modbus TCP** with zero external dependencies.

![Sigenergy widget preview](preview.png)

## Features

- **Live bar pill:** Shows live **Solar generation** (automatically appears whenever PV > 0 W), **Home load**, and **Battery State of Charge** with a distinct home-battery icon (`󱤁` / `󱤃` while charging).
- **Color-coded Battery SoC:** Battery icon, percentage, and progress bar dynamically shift by charge level — **Red** (`< 20%`), **Amber** (`20% – 50%`), and **Green** (`> 50%`).
- **Theme-native popup card:** Follows your active Omarchy theme colors, fonts, corner radius, and motion settings live.
- **Live power flow tiles:** Solar (PV), Home Load, and Grid (with Importing / Exporting / Balanced state).
- **Today's energy breakdown:** Solar generated, Home load, Battery charged & discharged, Net Grid balance, and Battery health (SoH % + average cell temperature).
- **Zero Python dependencies:** Pure Python 3 standard library (`socket` + `struct`) Modbus TCP client.

## Prerequisites & Finding Your Sigenergy IP / Port

Before the widget can read live data, your Sigenergy system needs to be reachable over local **Modbus TCP**:

1. **Same local network (avoid Guest Wi-Fi):** Make sure your Omarchy PC and your Sigenergy inverter/controller are connected to the **same main Wi-Fi or Ethernet LAN**. Guest/IoT Wi-Fi networks (such as Google/Nest Guest Wi-Fi) enable client isolation and will block local connections even if both devices are on it.
2. **Enable Modbus TCP (default port `502`):** Open the **mySigen** app and enable **Modbus TCP** under your inverter/system communication settings. The default port is **`502`**. *(If the setting is not visible in your app, ask your solar installer to enable local Modbus TCP.)*
3. **Find your Sigenergy IP address:**
   - **In the mySigen app:** Check the device's Wi-Fi / Ethernet network details for its local IP (e.g. `192.168.1.50` or `192.168.86.20`).
   - **In your router app/admin page:** Look for the Sigenergy / Espressif device on your main network.
   - **Or ask an AI agent on your Omarchy PC:** Make sure your Sigenergy battery is on the same network as your PC, then ask your AI agent to check your Sigenergy IP/port `502` and configure `~/.config/omarchy/shell.json` for you.

## Installation

```bash
omarchy plugin add https://github.com/mahmudurah/omarchy-sigenergy --enable
```

Then find the `io.github.mahmudurah.sigenergy` entry in `~/.config/omarchy/shell.json` and set **`"host"`** to your Sigenergy IP address (keep **`"id"`** as-is — it identifies the plugin, not a network address):

```json
{
  "id": "io.github.mahmudurah.sigenergy",
  "host": "192.168.1.50",
  "port": 502,
  "refreshSeconds": 15,
  "barMode": "full"
}
```

### Verify Connection

You can test your IP and port directly from a terminal (replace `192.168.1.50` with your Sigenergy IP):

```bash
python3 ~/.config/omarchy/plugins/io.github.mahmudurah.sigenergy/scripts/poll.py 192.168.1.50 502
```

If everything is set up correctly, it prints a JSON object starting with `{"ok": true, ...}`.

### Configuration Options

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `host` | string | `""` | Local IP address of your Sigenergy Energy Controller / Inverter |
| `port` | number | `502` | Modbus TCP port (`502` is the Sigenergy default) |
| `refreshSeconds` | number | `15` | Background polling interval in seconds (polls every 5 s while card is open) |
| `barMode` | string | `"full"` | Bar display mode: `full` (Solar + Home + SoC), `soc` (SoC only), or `icon` |

## Controls

- **Left-click:** Toggle the popup card
- **Right-click:** Cycle bar mode (`full` → `soc` → `icon`)
- **Middle-click:** Force an immediate refresh
- **Keyboard (when open):** `R` to refresh, `Esc` to close, `Tab` / `Shift+Tab` to switch panels
- **CLI / IPC:** `omarchy-shell io.github.mahmudurah.sigenergy toggle`

## Troubleshooting

- **Shows `Setup` on the bar:** `"host"` is still empty in `~/.config/omarchy/shell.json`. Add your Sigenergy IP and save.
- **Shows `off` / times out:** Check that both your PC and Sigenergy are on the same main LAN (not Guest Wi-Fi) and that **Modbus TCP** is enabled in the mySigen app on port `502`.

## Removal

```bash
omarchy plugin remove io.github.mahmudurah.sigenergy
```

## License

MIT — see [LICENSE](LICENSE).
