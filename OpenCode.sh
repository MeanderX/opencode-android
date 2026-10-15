#!/data/data/com.termux/files/usr/bin/bash
# Termux:Widget home-screen shortcut — tap the "OpenCode" widget to launch.
#
# Requires the Termux:Widget app installed from the same source as Termux
# (F-Droid or GitHub releases). Long-press your home screen, pick
# Widgets -> Termux:Widget, and drag "OpenCode.sh" onto it.
#
# This is a thin wrapper: all of the work, including the daily OpenCode
# auto-update, lives in the `oc` launcher it hands over to, so the widget
# and the terminal stay in step. Set OC_NO_AUTOUPDATE=1 to turn the
# auto-update off.
exec "$PREFIX/bin/oc"
