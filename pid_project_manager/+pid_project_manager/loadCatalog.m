function catalog = loadCatalog(projectRoot)
%LOADCATALOG Load a previously saved PID catalog.
path = pid_project_manager.catalogPath(string(projectRoot));
if ~isfile(path)
    error("PIDAgent:CatalogNotFound", "PID catalog does not exist: %s", path);
end
catalog = jsondecode(fileread(path));
end