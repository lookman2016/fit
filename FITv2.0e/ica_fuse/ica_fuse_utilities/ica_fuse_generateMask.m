function [avgMask, maskFileName] = ica_fuse_generateMask(files, varargin)
%% Generate default mask. Default mask is generated by averaging the individual subject masks. Individual subject masks includes voxels above or equalling the mean.
% After the mask is generated, batch file is written out using the current mask.
%
% Inputs:
%
% 1. files - Character array of file names
% 2. varargin - Variable number of arguments
%   a. multiplier - Multiplier applied to the mean. Default is 1.
%   b. threshold - Average mask threshold.
%   c. prefix - Output prefix
%   d. outputDir - Output directory
%   e. corr_threshold - Threshold to exclude outliers based on correlation
%

ica_fuse_defaults;
global FIG_FG_COLOR;

%% Initialze vars
% Default mask multiplier (data >= mult*mean)
mult = 1;
% Mask Threshold
threshold = 0.7;
% Prefix
prefix = 'ica_analysis';
% Output directory
outputDir = '';
disp_corr = 1;
for n = 1:2:length(varargin)
    if (strcmpi(varargin{n}, 'multiplier'))
        mult = varargin{n + 1};
    elseif (strcmpi(varargin{n}, 'threshold'))
        threshold = varargin{n + 1};
    elseif (strcmpi(varargin{n}, 'prefix'))
        prefix = varargin{n + 1};
    elseif (strcmpi(varargin{n}, 'outputdir'))
        outputDir = varargin{n + 1};
    elseif (strcmpi(varargin{n}, 'corr_threshold'))
        corr_threshold = varargin{n + 1};
    elseif (strcmpi(varargin{n}, 'disp_corr'))
        disp_corr = varargin{n + 1};
    end
end

showGUI = 0;
if (isempty(outputDir))
    outputDir = ica_fuse_selectEntry('title', 'Select analysis output directory', 'typeEntity', 'directory');
end

if (isempty(outputDir))
    outputDir = pwd;
end

if (~exist('files', 'var') || isempty(files))
    showGUI = 1;
    files = ica_fuse_selectEntry('title', 'Select Nifti files of all subjects ...', 'typeEntity', 'file', 'typeSelection', 'multiple', 'filter', '*.img;*.nii');
end

drawnow;

files = cellstr(files);

if (showGUI)
    
    prompt= {'Enter mask multiplier (voxels >= multiplier*mean(voxels)', 'Enter average mask threshold', 'Enter output prefix'};
    defaultanswer = {num2str(mult), num2str(threshold), prefix};
    
    answers = ica_fuse_inputdlg2(prompt, 'Mask options', 1, defaultanswer);
    
    if (isempty(answers))
        error('Input gui is closed');
    end
    
    mult = str2num(answers{1});
    threshold = str2num(answers{2});
    prefix = answers{3};
    
end

drawnow;

disp('Generating mask ...');

time_points = zeros(1, length(files));

for nF = 1:length(files)
    currentFileN = files{nF};
    [pathstr, fN, extn] = fileparts(currentFileN);
    filesP = ica_fuse_listFiles_inDir(pathstr, [fN, extn]);
    if (isempty(filesP))
        error(['Files doesn''t exist. Please check the file pattern ', currentFileN]);
    end
    filesP = ica_fuse_fullFile('directory', pathstr, 'files', filesP);
    filesP = ica_fuse_rename_4d_file(filesP);
    time_points(nF) = size(filesP, 1);
    filesP = deblank(filesP(1,:));
    disp(['Loading ', filesP, ' ...']);
    [tmp_dat, HInfo] = ica_fuse_loadData(filesP);
    tmp_mask = double(tmp_dat >= mult*mean(tmp_dat(:)));
    
    if (nF == 1)
        masks = zeros(numel(tmp_mask), length(files));
    end
    
    masks(:, nF) = tmp_mask(:);
    
end

avgMaskT = mean(masks, 2);

correlations = abs(ica_fuse_corr(avgMaskT, masks));

avgMaskT = double(avgMaskT >= threshold);

if (isempty(find(avgMaskT == 1)))
    error('No voxels found in brain. Change the threshold and mask multiplier settings');
end

avgMaskT = reshape(avgMaskT, HInfo.dim(1:3));

[L, NUM] = ica_fuse_spm_bwlabel(avgMaskT, 26);

comps = zeros(1, NUM);

for ii = 1:NUM
    comps(ii) = length(find(L == ii));
end

[numInds, max_inds] = max(comps);

avgMask = double(L == max_inds);


%% Write mask
writeV = HInfo(1);
maskFile = fullfile(outputDir, [prefix, 'Mask.nii']);
writeV.fname = maskFile;
ica_fuse_write_vol(writeV, avgMask);

if (disp_corr)
    axesTitle = 'Individual mask correlations w.r.t average mask';
    fH = ica_fuse_getGraphics(axesTitle, 'timecourse', 'mask_corr', 'on');
    axH = axes('units', 'normalized', 'position', [0.15, 0.15, 0.7, 0.7]);
    set(fH, 'resize', 'on');
    plot((1:length(files)), correlations, 'm', 'linewidth', 1.5, 'parent', axH);
    title(axesTitle, 'parent', axH);
    set(axH, 'Xcolor', FIG_FG_COLOR);
    set(axH, 'Ycolor', FIG_FG_COLOR);
    xlabel('Subjects', 'parent', axH);
    ylabel('Correlations', 'parent', axH);
    axis(axH, 'tight');
end

if (~exist('corr_threshold', 'var'))
    prompt={'Enter correlation threshold to remove subject outliers from the analysis.'};
    name = 'Correlation threshold';
    numlines = 1;
    defaultanswer = {num2str(0.8)};
    answer = ica_fuse_inputdlg2(prompt, name, numlines, defaultanswer);
    
    if (~isempty(answer))
        corr_threshold = str2num(answer{1});
    end
end

filesIn = find(correlations >= corr_threshold);


masks = reshape((masks == 1), [HInfo(1).dim(1:3), size(masks, 2)]);
maskFileName = fullfile(outputDir, [prefix, '_mask_info.mat']);
save(maskFileName, 'masks', 'avgMask', 'mult', 'threshold', 'corr_threshold', 'correlations');

