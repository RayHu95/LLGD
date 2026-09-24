function line_segments = frameLSD(img_pose)
    line_segments = cell(numel(img_pose), 1);
    for i = 1:numel(img_pose)
        line_segments{i} = robustLineDetection(img_pose(i).Image, ...
            'Method', 'custom_lsd', 'MinLength', 8);
    end
end
