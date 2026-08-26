# OmTeleprompt

Teleprompter for interviewers and streamers with word tracking, voice activation, and pause-on-speak.

## Features

- **Word Tracking**: Highlights the current word as the teleprompter scrolls
- **Voice Activated**: Uses your microphone to detect when you're speaking
- **Pause When Speaking**: Automatically pauses the teleprompter when voice is detected
- **Write During Speaking**: Notes panel lets you jot down thoughts while the teleprompter is running
- **Adjustable Speed**: Control scroll speed from 0.5x to 5.0x
- **Edit Mode**: Switch between edit and read modes seamlessly

## Install

```sh
omarchy plugin add https://github.com/seyhunakyurek/omteleprompt.git --enable
```

Or manually clone into your plugins directory:

```sh
mkdir -p ~/.config/omarchy/plugins/io.github.seyhunakyurek.omteleprompt
cd ~/.config/omarchy/plugins/io.github.seyhunakyurek.omteleprompt
# copy all plugin files here
omarchy plugin enable io.github.seyhunakyurek.omteleprompt --section right
```

## Usage

1. Click the **📝** icon in your Omarchy bar to open OmTeleprompt
2. Click **✏️ Edit** and paste or type your script
3. Click **📖 Read Mode** to start the teleprompter
4. Use **▶ Play** to start auto-scrolling
5. Enable **🎤 Voice On** to activate pause-on-speak
6. Use the **Notes** panel to write while the teleprompter is running

## Voice Activation

Voice activation uses real-time audio analysis to detect when you're speaking. When enabled:
- The teleprompter automatically pauses when you speak
- A green indicator shows "Listening" when ready
- A red indicator shows "Speaking..." when voice is detected
- The teleprompter resumes when you stop speaking

### Dependencies

Voice activation requires one of these Python audio backends:

```sh
# Option 1: PyAudio (recommended)
pip install pyaudio

# Option 2: sounddevice
pip install sounddevice

# Option 3: arecord (usually pre-installed on Arch/Hyprland systems)
sudo pacman -S alsa-utils
```

If no backend is available, the teleprompter will still work in manual mode.

## Configure

```sh
# Move the widget in your bar
omarchy bar move io.github.seyhunakyurek.omteleprompt --section right

# Change default settings
omarchy plugin enable io.github.seyhunakyurek.omteleprompt --section right --config '{"fontSize": 40, "scrollSpeed": 1.5, "voiceEnabled": true, "vadThreshold": 400}'
```

## Remove

```sh
omarchy plugin remove io.github.seyhunakyurek.omteleprompt
```

## Keyboard Shortcuts

- **Escape**: Close the teleprompter panel
- **Tab**: Switch between panels (when multiple are open)

## Troubleshooting

- **Voice not working**: Install `pyaudio` or `sounddevice` Python packages
- **Panel won't open**: Run `omarchy-shell shell rescanPlugins`
- **Text not scrolling**: Make sure you have words in the script editor
- **Permission denied**: Ensure `bin/vad.py` is executable

## License

MIT
