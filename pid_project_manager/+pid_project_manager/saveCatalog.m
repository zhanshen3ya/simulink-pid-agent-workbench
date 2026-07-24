function path = saveCatalog(catalog)
%SAVECATALOG Persist a PID catalog outside the public source tree.
path = pid_project_manager.catalogPath(string(catalog.projectRoot));
folder = fileparts(path);
if ~isfolder(folder)
    mkdir(folder);
end
pid_tuning_core.writeJsonFile(path, catalog);
end