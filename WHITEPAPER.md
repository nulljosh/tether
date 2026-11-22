# Tether

## The problem

A Bluetooth mouse drops. It happens after sleep, after a battery swap, after the Mac decides it knows better.

Now the keyboard is all you have. Bluetooth settings want a click. So does every fix.

That's the trap.

## Why the obvious fix fails

The obvious fix is a script: find the mouse, call connect. We had one. It froze.

Here's why. Some mice take a new address every time you pair them again. The old entries stay behind in Bluetooth settings, three or four of them, all with the same name. A script calls connect on each one in turn. A dead address doesn't fail fast. It blocks for about fifteen seconds. Three dead ones and you're staring at nothing for most of a minute.

## What Tether does

Tether calls every saved copy of the mouse at the same time. Each call gets its own thread. The live one answers in a second or two, and the dead ones time out in the background where nobody waits on them.

Then it watches. Every half second it asks macOS one question: is any of these connected? The moment the answer is yes, the screen turns green.

If the mouse drops again while Tether is open, it starts over on its own.

## Built for no pointer

Everything works from the keyboard. Command Space, type Tether, Return. It starts connecting the moment the window opens. Return closes it once the mouse is back. Escape closes it any time.

If the mouse doesn't answer, Tether says what to do in plain words. Flip the switch underneath. Or press Return to open Bluetooth settings.

## What it doesn't do

Tether doesn't pair a new mouse. Pairing a Bluetooth LE mouse goes through the Nearby Devices list in System Settings, and macOS keeps that door closed to apps.

It doesn't forget old entries either. macOS ignores that request for LE devices. Clean those up once in Settings and they stay gone.

It doesn't show battery. macOS keeps an LE mouse's battery level to itself.

## How it's built

One Swift file. SwiftUI for the window, IOBluetooth for the radio. No Xcode project, no packages, no network code.

`build.sh` compiles it with swiftc, builds the icon with actool, signs it with a Developer ID, and drops it in Applications. The signature matters. macOS ties the Bluetooth permission to it, so a stable signature means you answer that prompt once, not after every build.

## Privacy

No account. No analytics. No network. Tether reads the list of devices you already paired and talks to the ones named like a mouse. Nothing is written to disk and nothing leaves the Mac.

## License

MIT. Take it, change it, ship it.
