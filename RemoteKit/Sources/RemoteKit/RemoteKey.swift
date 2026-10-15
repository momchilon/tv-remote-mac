/// Consumer-facing Samsung remote keys only. Availability depends on the TV and active app.
/// Service/factory commands, unknown EXT codes and unconfirmed power variants are intentionally excluded.
public enum RemoteKey: String, CaseIterable, Sendable {
    case up = "KEY_UP", down = "KEY_DOWN", left = "KEY_LEFT", right = "KEY_RIGHT"
    case enter = "KEY_ENTER", back = "KEY_RETURN", home = "KEY_HOME"
    case volumeUp = "KEY_VOLUP", volumeDown = "KEY_VOLDOWN", mute = "KEY_MUTE"
    case source = "KEY_SOURCE", power = "KEY_POWER"

    case exit = "KEY_EXIT", menu = "KEY_MENU", tools = "KEY_TOOLS", info = "KEY_INFO"
    case guide = "KEY_GUIDE", channelList = "KEY_CH_LIST", previousChannel = "KEY_PRECH"
    case channelUp = "KEY_CHUP", channelDown = "KEY_CHDOWN", favourites = "KEY_FAVCH"
    case liveTV = "KEY_TV", tvMode = "KEY_TV_MODE", digitalTV = "KEY_DTV"
    case antenna = "KEY_ANTENA", signalInfo = "KEY_DTV_SIGNAL"

    case digit0 = "KEY_0", digit1 = "KEY_1", digit2 = "KEY_2", digit3 = "KEY_3", digit4 = "KEY_4"
    case digit5 = "KEY_5", digit6 = "KEY_6", digit7 = "KEY_7", digit8 = "KEY_8", digit9 = "KEY_9"
    case plus100 = "KEY_PLUS100"
    case red = "KEY_RED", green = "KEY_GREEN", yellow = "KEY_YELLOW", blue = "KEY_BLUE"

    case play = "KEY_PLAY", pause = "KEY_PAUSE", stop = "KEY_STOP"
    case rewind = "KEY_REWIND", fastForward = "KEY_FF", record = "KEY_REC"
    case repeatPlayback = "KEY_REPEAT", instantReplay = "KEY_INSTANT_REPLAY", quickReplay = "KEY_QUICK_REPLAY"

    case smartHub = "KEY_CONTENTS", appList = "KEY_APP_LIST", more = "KEY_MORE", help = "KEY_HELP"
    case ambient = "KEY_AMBIENT", multiView = "KEY_MULTI_VIEW", anynet = "KEY_ANYNET"
    case deviceConnect = "KEY_DEVICE_CONNECT", mediaLink = "KEY_W_LINK"
    case discMenu = "KEY_DISC_MENU", dvr = "KEY_DVR", dvrMenu = "KEY_DVR_MENU", topMenu = "KEY_TOPMENU"

    case hdmi = "KEY_HDMI", hdmi1 = "KEY_HDMI1", hdmi2 = "KEY_HDMI2", hdmi3 = "KEY_HDMI3", hdmi4 = "KEY_HDMI4"
    case av1 = "KEY_AV1", av2 = "KEY_AV2", av3 = "KEY_AV3"
    case component1 = "KEY_COMPONENT1", component2 = "KEY_COMPONENT2"
    case sVideo1 = "KEY_SVIDEO1", sVideo2 = "KEY_SVIDEO2", sVideo3 = "KEY_SVIDEO3"
    case pc = "KEY_PCMODE", dvi = "KEY_DVI"

    case pictureMode = "KEY_PMODE", pictureSize = "KEY_PICTURE_SIZE", aspect = "KEY_ASPECT"
    case widescreen = "KEY_16_9", standardAspect = "KEY_4_3", zoom1 = "KEY_ZOOM1", zoom2 = "KEY_ZOOM2"
    case zoomIn = "KEY_ZOOM_IN", zoomOut = "KEY_ZOOM_OUT", zoomMove = "KEY_ZOOM_MOVE", panorama = "KEY_PANORAMA"
    case dynamicPicture = "KEY_DYNAMIC", standardPicture = "KEY_STANDARD", moviePicture = "KEY_MOVIE1"
    case freezePicture = "KEY_STILL_PICTURE", game = "KEY_GAME", energySaving = "KEY_ESAVING"

    case soundEffect = "KEY_SEFFECT", surround = "KEY_SRS", audioTrack = "KEY_MTS"
    case audioDescription = "KEY_AD", mainSubAudio = "KEY_CONVERT_AUDIO_MAINSUB"
    case captions = "KEY_CAPTION", subtitles = "KEY_SUB_TITLE", teletext = "KEY_TTX_MIX", teletextSubpage = "KEY_TTX_SUBFACE"

    case pip = "KEY_PIP_ONOFF", pipChannelUp = "KEY_PIP_CHUP", pipChannelDown = "KEY_PIP_CHDOWN"
    case pipSwap = "KEY_PIP_SWAP", pipSize = "KEY_PIP_SIZE", pipScan = "KEY_PIP_SCAN"
    case sleep = "KEY_SLEEP", clock = "KEY_CLOCK_DISPLAY", timer = "KEY_SETUP_CLOCK_TIMER"
}
