function handles=PlotData2(data,varargin)
%% handles=PlotData(data,'option',value)
% Purpose: plot data in various ways depending on what data was provided
% and what options are defined. this function is wrapped by PlotWaveforms,
% PlotPower, ... to provide a single function for organizing and displaying
% data.
% Inputs:
%   data: DynaSim data structure (see CheckData)
%   Accepts the following name/value pairs:
%     'plot_type' {'waveform' (default),'rastergram','rates','power'} - what to plot
%     'population' - name of population to plot (default: 'all'); accepts
%                    regexp strings
%     'variable' - name of variable to plot for each population (default: state variable, X or V);
%                      accepts regexp strings
%     'varied1' - Indices of 1st varied model parameter to plot. If the parameter
%                 is numeric, specify indices (e.g. 1:3 corresponds to 1st-3rd
%                 varied values. If the parameter is a char array, uses
%                 regular expressions. Instead of 'varied1', can also use
%                 the actual parameter name (e.g. 'E_Iapp')
%     'varied2' - As varied 1, for 2nd varied parameter
%     'num_embedded_subplots' - maximum # of waveforms to overlay per plot
%     'max_num_overlaid' - maximum # of waveforms to overlay per plot
%     'do_mean' - {false, true} - Turn on/off averaging across all units
%                 in a population
%     'force_overlay' - {'none', 'populations' (default), 'variables', 'varied1' ... 'variedN'}
%                       If there is only one cell in a population, this forces
%                       PlotData2 to add other information to the overlay.
%     'xlims' - [XMIN XMAX], x-axis limits (default: all data)
%     'ylims' - [YMIN YMAX], y-axis limits (default: all data)
%     'do_zoom' - {false, true} - Turn on zoom function in subplot_grid
%     'yscale' {'linear','log','log10'}, whether to plot linear or log scale
%     'visible' {'on','off'}
%     NOTE: analysis options available depending on plot_type
%       see see CalcFR options for plot_type 'rastergram' or 'rates'
%       see CalcPower options for plot_type 'power'
% Outputs:
%   handles: graphic handles to figures
% 
% See also: CalcFR, CalcPower, PlotWaveforms, CheckData

% Check inputs
data=CheckData(data);
  % note: calling CheckData() at beginning enables analysis/plotting functions to
  % accept data matrix [time x cells] in addition to DynaSim data structure.

  % Flag for returning error if the user specifies name/value pairs that are not in the
  % CheckOptions list
  strict_mode = 0;
  
[options, options_extras0] = CheckOptions(varargin,{...
  'population',[],[],...        
  'variable',[],[],...        
  'num_embedded_subplots',2,[{1,2,3,4}],...
  'max_num_overlaid',50,[],...
  'do_mean',false,[false true],...
  'force_overlay',[],[],...
  'plot_type','waveform',{'waveform','waveform_mean','rastergram','raster','power','rates'},...
  'xlim',[],[],...
  'ylim',[],[],...
  'plot_options',struct,[],...
  'subplot_options',struct,[],...
  'do_zoom',false,[false true],...
  'yscale','linear',{'linear','log','log10','log2'},...
  'visible','on',{'on','off'},...
  'save_data','on',{'on','off'},...
  },false);
handles=[];

% Pull out fields from options struct
plot_options = options.plot_options;
subplot_options = options.subplot_options;
num_embedded_subplots = options.num_embedded_subplots;
do_mean = options.do_mean;
force_overlay = options.force_overlay;

% Add default options to structures
% Plot_options
plot_options = struct_addDef(plot_options,'ylims',options.ylim);
plot_options = struct_addDef(plot_options,'xlims',options.xlim);

% Subplot_options
subplot_options = struct_addDef(subplot_options,'subplotzoom_enabled',options.do_zoom);


% todo: add option 'plot_mode' {'trace','image'}

time=data.time;

% do any analysis if necessary and set x-data
switch options.plot_type
  case 'waveform'   % plot VARIABLE
    xdata=time;
    xlab='time (ms)'; % x-axis label
  case 'power'      % plot VARIABLE_Power_SUA.Pxx
    if any(cellfun(@isempty,regexp(var_fields,'.*_Power_SUA$')))
      data=CalcPower(data,varargin{:});
    end
    xdata=data(1).([var_fields{1} '_Power_SUA']).frequency;
    xlab='frequency (Hz)'; % x-axis label
    % set default x-limits for power spectrum
    if isempty(options.xlim)
      options.xlim=[0 200]; % Hz
    end
  case {'rastergram','raster'} % raster VARIABLE_spike_times
    if any(cellfun(@isempty,regexp(var_fields,'.*_spike_times$')))
      data=CalcFR(data,varargin{:});
    end
    xdata=time;
    xlab='time (ms)'; % x-axis label
  case 'rates'      % plot VARIABLE_FR
    if any(cellfun(@isempty,regexp(var_fields,'.*_FR$')))
      data=CalcFR(data,varargin{:});
    end
    xdata=data.time_FR;
    xlab='time (ms, bins)'; % x-axis label
end
% if isempty(options.xlim)
%   options.xlim=[min(xdata) max(xdata)];
% end

% Import DynaSim data to xPlt
xp = DynaSim2xPlt(data);

% Find out names of varied variables
all_names = xp.exportAxisNames;
varied_names = only_varieds(all_names);  % Returns only the names of the varied variables


% Convert 'varied1'...'variedN' values in options extra to the names of the
% actual parameters
options = convert_variedN_to_axisnames(varied_names,options);
options_extras = convert_variedN_to_axisnames(varied_names,options_extras0);


% Average across cells if necessary
if do_mean 
    mydata = xp.data;
    mydata = cellfun(@(x) mean(x,2), mydata,'UniformOutput',0);
    xp.data = mydata;
    xp.meta.datainfo(2).values = {'<Cells>'};
end


% Apply max overlaid
MTPP = options.max_num_overlaid; % max traces per plot
if any(strcmp(options.plot_type,{'waveform','power'})) && all(cellfun(@isnumeric,xp.data(:)))
    mydata = xp.data;
    mydata2 = cell(size(mydata));
    for i = 1:numel(mydata)
        if ~isempty(mydata{i})
            mydata2{i} = mydata{i}(:,1:min(size(mydata{i},2),MTPP));
        end
    end
    
    xp.data = mydata2;
    clear mydata mydata2
    
    % Update cell numbers metadata
    cell_names = [1:max(cellfun(@(x) size(x,2),xp.data(:)))];
    cell_names_str = cellfunu(@(s) ['Cell ' num2str(s)], num2cell(cell_names));
    xp.meta.datainfo(2).values = cell_names_str;
end


% Axis indices of populations
ax_ind_var = xp.findaxis('variables');
ax_ind_pop = xp.findaxis('population');
ax_ind_varied = get_ax_ind_varied(xp);
ax_ind_varied = find(ax_ind_varied);

% Permute to put varied variables last
xp = permute(xp,[ax_ind_var, ax_ind_pop, ax_ind_varied(:)']);


% User selection for populations
chosen_pop = options.population;
if isempty(chosen_pop)
    chosen_pop = ':';
end

% User selection for variables
chosen_vars = options.variable;
if isempty(chosen_vars)
    chosen_vars = getdefaultvar(xp);
end

% User selection for varied parameters
[chosen_varied , options_extras ]= get_chosen_varied(varied_names,options_extras);

% If any options are still leftover, these are extraneous. Report an error
leftover_fields = fieldnames(options_extras);
if ~isempty(leftover_fields) && strict_mode
    error('The following unrecogized name/value pairs were passed in: %s', sprintf('%s ',leftover_fields{:}));
end

% Convert any "all" strings in chosen_varied to colon operators
inds = cellfun(@ischar,chosen_varied);
chosen_varied(inds) = cellfun(@(s) strrep(s,'all',':'),chosen_varied(inds),'UniformOutput',0);

% Select out chosen data
xp2 = xp(chosen_vars,chosen_pop,chosen_varied{:});

% Assign default value to force_overlay
if isempty(force_overlay) 
    if length(xp2.meta.datainfo(2).values) <= 1
        force_overlay = 'populations';
    else
        force_overlay = 'none';
    end
end

if ~strcmpi(force_overlay,'none')
    ax_num = xp2.findaxis(force_overlay);
    if length(ax_num) > 1; error('force_overlay: Ambiguous axis specified. Can only pack at most 1 axis');
    elseif isempty(ax_num)
        error('force_overlay: Cannot find requested axis');
    end
    
    % Save variables associated with this axis
    packed_vars = xp2.axis(ax_num).values;
    packed_name = xp2.axis(ax_num).name;
    
    % Add <average> symbols if necessary to packed_vars
    cellnames = xp2.meta.datainfo(2).values;
    temp = cellfun(@isempty,strfind(cellnames,'<'));    % Check if originals were averages!
    if any(~temp)
        packed_vars = cellfunu(@(s) ['<' s '>'], packed_vars);
    end
    
    % Add this new info to datainfo
    % If there is still more than 1 cell present, bump this data down a
    % dimension.
    only_one_cell = length(xp2.meta.datainfo(2).values) == 1;
    if ~only_one_cell
        xp2.meta.datainfo(end+1) = xp2.meta.datainfo(end);
    end
    xp2.meta.datainfo(end).name = packed_name;
    xp2.meta.datainfo(end).values = packed_vars(:)';
    
    
    
    % Pack the dimension into the first empty dimension
    xp2 = xp2.packDim(force_overlay);
    if only_one_cell
        xp2.data = cellfunu(@squeeze,xp2.data);
    end
end

% Make sure xp2.data is not more than 3 dimensions (this is the most we can
% plot in a single subplot)


% Squeeze to eliminate superfluous dimensions
xp2 = xp2.squeeze;
Nd = ndims(xp2);


subplot_options.legend1 = xp2.meta.datainfo(2).values;

% Split available axes into the number of dimensions supported by each
% axis handle
switch num_embedded_subplots
    case 1
        % Ordering of axis handles
        function_handles = {@xp_handles_newfig, @xp_subplot_grid,@xp_matrix_basicplot};   % Specifies the handles of the plotting functions
        dims_per_function_handle = [1,1,1];
        function_args = {{},{subplot_options},{plot_options}};
        
    case 2
        % Ordering of axis handles
        function_handles = {@xp_handles_newfig, @xp_subplot_grid,@xp_matrix_basicplot};   % Specifies the handles of the plotting functions
        dims_per_function_handle = [1,2,1];
        function_args = {{},{subplot_options},{plot_options}};
        
    case 3
        % Ordering of axis handles
        function_handles = {@xp_handles_newfig, @xp_subplot_grid, @xp_subplot_grid,@xp_matrix_basicplot};   % Specifies the handles of the plotting functions
        dims_per_function_handle = [1,2,1,1];
        subplot_options2 = subplot_options;
        subplot_options2.legend1 = [];
        subplot_options.display_mode = 1;
        function_args = {{},{subplot_options2},{subplot_options},{plot_options}};
    case 4
        % Ordering of axis handles
        function_handles = {@xp_handles_newfig, @xp_subplot_grid, @xp_subplot_grid,@xp_matrix_basicplot};   % Specifies the handles of the plotting functions
        dims_per_function_handle = [1,2,2,1];
        subplot_options2 = subplot_options;
        subplot_options2.legend1 = [];
        subplot_options.display_mode = 1;
        function_args = {{},{subplot_options2},{subplot_options},{plot_options}};
end

% Linearize dimensions of xp2 that are in excess of the total number we can
% plot
maxNplotdims = sum(dims_per_function_handle)-1;
xp2 = reduce_dims(xp2,maxNplotdims);

% Stack up available dimensions based on how much each axis handle can hold
ax_names = [xp2.exportAxisNames, 'data'];
dimensions = get_dimensions(ax_names,dims_per_function_handle);

% Remove any excess function handles that aren't needed
available_dims = ~cellfun(@isempty,dimensions);
function_handles = function_handles(available_dims);
dimensions = dimensions(available_dims);
function_args = function_args(available_dims);

% Open new figure if necessary & plot the data
if ~isequal(@xp_handles_newfig, function_handles{1}); figl; end
xp2.recursivePlot(function_handles,dimensions,function_args);


end

function vars_out = getdefaultvar(xp)
    % search through and try to find the variable represnting voltage. If can't find
    % it, just return the first variable listed.
    
    
    % Pull out variables
    vars_orig = xp.axis('variables').values;
    
    % Make everything uppercase to ensure
    % case-insensitive.
    vars = upper(vars_orig);
    possibilities = upper({'V','X','Vm','Xm','Y','Ym'});
    
    ind = [];
    i=0;
    while isempty(ind) && i < length(possibilities)
        i=i+1;
        ind = find(strcmpi(vars,possibilities{i}));
    end
    
    if ~isempty(ind)
        vars_out = vars_orig{ind};
    else
        vars_out = vars_orig{1};
    end
end

function [chosen_varied, options_varied ]= get_chosen_varied(varied_names,options_varied)

    
    
    
    % Initialize output
    chosen_varied = repmat({':'},1,length(varied_names));
    
    % Varied name-value pairs entered by user
    varied_NVPs = fieldnames(options_varied);
    
    % See if any of these match actual varied parameters
    for i =  1:length(varied_NVPs)
        ind = find(strcmp(varied_names,varied_NVPs{i}));
        if length(ind) == 1
            chosen_varied{ind} = options_varied.(varied_NVPs{i});
            
            % Optional (remove from options_varied)
            options_varied = rmfield(options_varied,varied_NVPs{i});
        elseif length(ind) > 1
            error('Multiple varied arguments found');
        else
            % Not a varied variable name
        end
        
        
    end
    
end

function options_extras = convert_variedN_to_axisnames(all_names,options_extras);

    fn = fieldnames(options_extras);
    fn2 = fn;
    for i = 1:length(fn)
        fn_curr = fn{i};
        if strcmp(fn_curr(1:min(6,end)),'varied')        % User has entered variedX
            % fn is original fieldname (e.g. variedX)
            % fn2 is new field name of varied parameter (e.g. E_Iapp)
            fn2{i} = all_names{str2num(fn_curr(7:end))};
            options_extras.(fn2{i}) = options_extras.(fn{i});
            options_extras = rmfield(options_extras,fn{i});
        end
    end
    

end

function ax_ind_varied = get_ax_ind_varied(xp)
    % get logical indices of axess corresponding to varied parameters
    ax_ind_pop = xp.findaxis('population');
    ax_ind_var = xp.findaxis('variables');
    ax_ind_varied = true(1,ndims(xp));
    if ~isempty(ax_ind_pop); ax_ind_varied(ax_ind_pop) = 0; end
    if ~isempty(ax_ind_var); ax_ind_varied(ax_ind_var) = 0; end
end

function dimensions = get_dimensions(ax_names,dims_per_function_handle)
    % Split available axes into the number of dimensions supported by each
    % axis handle

    i = length(dims_per_function_handle);
    while i > 0 && ~isempty(ax_names)
        
        Ndims_curr = dims_per_function_handle(i);
        dimensions{i} = ax_names(max(1,end-Ndims_curr+1):end);
        ax_names = ax_names(1:end-Ndims_curr);
        i=i-1;
    end
    
end



function xp2 = reduce_dims(xp2,maxNplotdims)
    Nd = ndims(xp2);
    if Nd > maxNplotdims 
        xp2 = xp2.mergeDims( [maxNplotdims:Nd] );
        xp2 = xp2.squeeze;
        Nd = ndims(xp2);

        if Nd ~= maxNplotdims; error('something wrong'); end
    end
end

function varied_names = only_varieds(all_names)
    inds = true(1,length(all_names));
    inds(strcmp(all_names,'populations')) = false; 
    inds(strcmp(all_names,'variables')) = false;
    varied_names = all_names(inds);
end