function path = catalogPath(projectRoot)
%CATALOGPATH Return the private project catalog path.
arguments
    projectRoot (1, 1) string
end
path = fullfile(projectRoot, ".pid-agent", "catalog.json");
end