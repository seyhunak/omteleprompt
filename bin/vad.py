#!/usr/bin/env python3
"""
Voice Activity Detection (VAD) script for OmTeleprompt.
Captures microphone audio and outputs events to stdout:
  VOICE_START - when speech is detected
  VOICE_END   - when speech stops
  LEVEL:xxx   - current audio level (for visualization)

Usage:
  python3 vad.py [--threshold VALUE]

Default threshold is 500 (0-32767 range for 16-bit audio).
Lower values = more sensitive.
"""

import sys
import time
import argparse
import math
import subprocess
import os

def calculate_rms(frame):
    """Calculate RMS energy of an audio frame."""
    if not frame:
        return 0.0
    sum_squares = sum(s * s for s in frame)
    return math.sqrt(sum_squares / len(frame))

def try_pyaudio(threshold):
    """Try to use PyAudio for real-time VAD."""
    try:
        import pyaudio
    except ImportError:
        return None

    CHUNK = 1024
    FORMAT = pyaudio.paInt16
    CHANNELS = 1
    RATE = 16000

    p = pyaudio.PyAudio()

    try:
        stream = p.open(format=FORMAT,
                        channels=CHANNELS,
                        rate=RATE,
                        input=True,
                        frames_per_buffer=CHUNK)
    except Exception as e:
        print(f"PyAudio stream error: {e}", file=sys.stderr)
        p.terminate()
        return None

    stream.start_stream()
    speaking = False
    silence_frames = 0
    SILENCE_LIMIT = 15  # frames of silence before declaring speech end

    try:
        while True:
            try:
                data = stream.read(CHUNK, exception_on_overflow=False)
            except Exception:
                break

            frame = list(data)
            rms = calculate_rms(frame)
            print(f"LEVEL:{rms:.0f}", flush=True)

            if rms > threshold:
                if not speaking:
                    speaking = True
                    silence_frames = 0
                    print("VOICE_START", flush=True)
                else:
                    silence_frames = 0
            else:
                if speaking:
                    silence_frames += 1
                    if silence_frames >= SILENCE_LIMIT:
                        speaking = False
                        print("VOICE_END", flush=True)

            time.sleep(0.01)
    except KeyboardInterrupt:
        pass
    finally:
        stream.stop_stream()
        stream.close()
        p.terminate()
    return True

def try_sounddevice(threshold):
    """Try to use sounddevice for real-time VAD."""
    try:
        import sounddevice as sd
        import numpy as np
    except ImportError:
        return None

    CHUNK = 1024
    RATE = 16000
    CHANNELS = 1

    speaking = False
    silence_frames = 0
    SILENCE_LIMIT = 15

    def audio_callback(indata, frames, time_info, status):
        nonlocal speaking, silence_frames
        if status:
            print(f"Sounddevice status: {status}", file=sys.stderr)
        frame = indata[:, 0] if indata.shape[1] > 0 else indata.flatten()
        rms = math.sqrt(np.mean(frame ** 2)) * 32767
        print(f"LEVEL:{rms:.0f}", flush=True)

        if rms > threshold:
            if not speaking:
                speaking = True
                silence_frames = 0
                print("VOICE_START", flush=True)
            else:
                silence_frames = 0
        else:
            if speaking:
                silence_frames += 1
                if silence_frames >= SILENCE_LIMIT:
                    speaking = False
                    print("VOICE_END", flush=True)

    try:
        with sd.InputStream(callback=audio_callback,
                            channels=CHANNELS,
                            samplerate=RATE,
                            blocksize=CHUNK):
            while True:
                time.sleep(0.1)
    except KeyboardInterrupt:
        pass
    except Exception as e:
        print(f"Sounddevice error: {e}", file=sys.stderr)
        return None
    return True

def try_parecord(threshold):
    """Fallback: use parecord (PulseAudio) and parse audio levels via pipe."""
    try:
        cmd = ["parecord", "--format=s16le", "--rate=16000", "--channels=1", "--device=@DEFAULT_SOURCE@", "/dev/stdout"]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except Exception as e:
        print(f"parecord error: {e}", file=sys.stderr)
        return None

    speaking = False
    silence_frames = 0
    SILENCE_LIMIT = 15
    CHUNK = 1024

    try:
        while True:
            data = proc.stdout.read(CHUNK * 2)
            if not data:
                break
            frame = list(data)
            rms = calculate_rms(frame)
            print(f"LEVEL:{rms:.0f}", flush=True)

            if rms > threshold:
                if not speaking:
                    speaking = True
                    silence_frames = 0
                    print("VOICE_START", flush=True)
                else:
                    silence_frames = 0
            else:
                if speaking:
                    silence_frames += 1
                    if silence_frames >= SILENCE_LIMIT:
                        speaking = False
                        print("VOICE_END", flush=True)

            time.sleep(0.01)
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
        proc.wait()
    return True

def try_arecord(threshold):
    """Fallback: use arecord and parse audio levels via pipe."""
    try:
        cmd = ["arecord", "-f", "S16_LE", "-r", "16000", "-c", "1", "-t", "raw", "-"]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except Exception as e:
        print(f"arecord error: {e}", file=sys.stderr)
        return None

    speaking = False
    silence_frames = 0
    SILENCE_LIMIT = 15
    CHUNK = 1024

    try:
        while True:
            data = proc.stdout.read(CHUNK * 2)
            if not data:
                break
            frame = list(data)
            rms = calculate_rms(frame)
            print(f"LEVEL:{rms:.0f}", flush=True)

            if rms > threshold:
                if not speaking:
                    speaking = True
                    silence_frames = 0
                    print("VOICE_START", flush=True)
                else:
                    silence_frames = 0
            else:
                if speaking:
                    silence_frames += 1
                    if silence_frames >= SILENCE_LIMIT:
                        speaking = False
                        print("VOICE_END", flush=True)

            time.sleep(0.01)
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
        proc.wait()
    return True

def main():
    parser = argparse.ArgumentParser(description="Voice Activity Detection for OmTeleprompt")
    parser.add_argument("--threshold", type=float, default=500.0, help="VAD threshold (0-32767)")
    args = parser.parse_args()

    print(f"VAD started with threshold {args.threshold}", file=sys.stderr)

    # Try backends in order of preference
    result = try_pyaudio(args.threshold)
    if result is None:
        result = try_sounddevice(args.threshold)
    if result is None:
        result = try_parecord(args.threshold)
    if result is None:
        result = try_arecord(args.threshold)

    if result is None:
        print("No audio backend available. Install pyaudio or sounddevice.", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
