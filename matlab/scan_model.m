function result = scan_model(modelFile)
%SCAN_MODEL Read a model without writing parameters or saving it.
result = build_block_graph(modelFile);
end
