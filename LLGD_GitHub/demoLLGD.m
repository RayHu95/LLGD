function [events, labels] = demoLLGD(showPlot)
    if nargin < 1, showPlot = true; end
    root = fileparts(mfilename('fullpath'));
    addpath(fullfile(root, 'LineDetection'));
    rng(2025, 'twister');
    width = 240; height = 180;
    x = (70:170)'; y = (50:130)';
    pixels = unique([x,50*ones(size(x)); x,130*ones(size(x)); ...
        70*ones(size(y)),y; 170*ones(size(y)),y], 'rows');
    points = repmat(pixels,4,1);
    timestamp = repelem((0:3)'*0.005,size(pixels,1));
    events = [points,ones(size(points,1),1),floor(timestamp), ...
        round((timestamp-floor(timestamp))*1e9)];

    detector = EventLineDBSCAN();
    detector.c_width = width;
    detector.c_height = height;
    detector.pointData = [points./[width,height],timestamp];
    labels = detector.EventSegmentation();
    fprintf('%d events, %d detected clusters\n',size(events,1), ...
        numel(unique(labels(labels>0))));
    if showPlot
        figure('Color','w');
        gscatter(events(:,1),events(:,2),labels);
        axis equal; xlim([0,width]); ylim([0,height]);
        set(gca,'YDir','reverse');
        xlabel('x (pixel)'); ylabel('y (pixel)');
        title('LLGD on a synthetic event packet');
    end
end
