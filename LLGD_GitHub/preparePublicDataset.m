function preparePublicDataset(datasetName, frameNum, windowDuration, frameRange)
    if nargin < 2
        frameNum = 30;
    end
    if nargin < 3
        windowDuration = 0.02;
    end

    datasetFolder = fullfile('datasets', datasetName);
    imageList = readtable(fullfile(datasetFolder, 'images.txt'), ...
        'FileType', 'text', 'ReadVariableNames', false);
    eventList = readmatrix(fullfile(datasetFolder, 'events.txt'));

    if nargin < 4
        frameRange = [10, height(imageList)-2];
    end
    frameIdx = round(linspace(frameRange(1), frameRange(2), frameNum));
    data = repmat(struct('Image', [], 'qR', [], 't', [], ...
        'eventsNum', 0, 'events', []), 1, frameNum);
    frameTime = zeros(frameNum, 1);
    startOffset = zeros(frameNum, 1);
    endOffset = zeros(frameNum, 1);

    for i = 1:frameNum
        idx = frameIdx(i);
        timeStart = imageList.Var1(idx);
        timeEnd = min(timeStart+windowDuration, imageList.Var1(idx+1));
        eventIdx = eventList(:,1) >= timeStart & eventList(:,1) < timeEnd;
        eventArray = eventList(eventIdx,:);

        sec = floor(eventArray(:,1));
        nsec = round((eventArray(:,1)-sec)*1e9);
        frameTime(i) = timeStart;
        startOffset(i) = eventArray(1,1)-timeStart;
        endOffset(i) = eventArray(end,1)-timeStart;
        data(i).Image = imread(fullfile(datasetFolder, imageList.Var2{idx}));
        data(i).events = [eventArray(:,2:3), eventArray(:,4), sec, nsec];
        data(i).eventsNum = size(eventArray,1);
    end

    [e_height, e_width] = size(data(1).Image);
    cam = {e_height, e_width, [], []};
    save(fullfile('datasets', [datasetName, '_events.mat']), ...
        'cam', 'data', 'frameIdx', 'frameTime', ...
        'startOffset', 'endOffset', '-v7.3');
    fprintf('Saved %s with %d event arrays.\n', datasetName, frameNum);
end
