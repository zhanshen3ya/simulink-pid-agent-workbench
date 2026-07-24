function blkStruct = slblocks
%SLBLOCKS Register the PID Agent launcher in the Simulink Library Browser.
browser.Library = "pid_agent_lib";
browser.Name = "PID Agent Manager";
browser.IsFlat = 1;
blkStruct.Browser = browser;
end