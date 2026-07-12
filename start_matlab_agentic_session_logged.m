diary('D:\matlab_agentic_toolkits\logs\matlab-agentic-session.log');
fprintf('Starting MATLAB Agentic Toolkit session at %s\n', datestr(now));
try
    run('D:\matlab_agentic_toolkits\start_agentic_matlab_session.m');
    fprintf('AGENTIC_SESSION_READY at %s\n', datestr(now));
catch ME
    fprintf('AGENTIC_SESSION_FAILED at %s\n', datestr(now));
    fprintf('%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
end
diary off;

