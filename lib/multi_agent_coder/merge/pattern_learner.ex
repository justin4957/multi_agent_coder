defmodule MultiAgentCoder.Merge.PatternLearner do
  @moduledoc """
  Learns from user resolution choices to improve automatic conflict resolution.

  Tracks patterns in user decisions and builds a preference model per user/project
  that can be used to predict optimal resolutions for future conflicts.
  """

  use GenServer
  require Logger

  alias MultiAgentCoder.FileOps.ConflictDetector

  @type resolution_record :: %{
          conflict_signature: String.t(),
          file_path: String.t(),
          file_type: String.t(),
          conflict_type: atom(),
          providers: list(atom()),
          chosen_resolution: term(),
          chosen_provider: atom() | nil,
          timestamp: DateTime.t(),
          context: map()
        }

  @type preference_model :: %{
          by_file_type: map(),
          by_provider: map(),
          by_conflict_type: map(),
          overall_accuracy: float(),
          total_resolutions: non_neg_integer()
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a user's resolution choice for learning.
  """
  @spec record_resolution(ConflictDetector.conflict(), term(), keyword()) :: :ok
  def record_resolution(conflict, chosen_resolution, opts \\ []) do
    GenServer.cast(__MODULE__, {:record_resolution, conflict, chosen_resolution, opts})
  end

  @doc """
  Predicts the best resolution for a conflict based on learned patterns.
  """
  @spec predict_resolution(ConflictDetector.conflict()) ::
          {:ok, term(), float()} | {:error, :insufficient_data}
  def predict_resolution(conflict) do
    GenServer.call(__MODULE__, {:predict_resolution, conflict})
  end

  @doc """
  Gets the learned preference model.
  """
  @spec get_preferences() :: preference_model()
  def get_preferences do
    GenServer.call(__MODULE__, :get_preferences)
  end

  @doc """
  Gets resolution history filtered by criteria.
  """
  @spec get_history(keyword()) :: list(resolution_record())
  def get_history(filters \\ []) do
    GenServer.call(__MODULE__, {:get_history, filters})
  end

  @doc """
  Clears all learned patterns.
  """
  @spec clear_history() :: :ok
  def clear_history do
    GenServer.call(__MODULE__, :clear_history)
  end

  @doc """
  Exports learned patterns to a file for persistence.
  """
  @spec export_patterns(String.t()) :: :ok | {:error, String.t()}
  def export_patterns(file_path) do
    GenServer.call(__MODULE__, {:export_patterns, file_path})
  end

  @doc """
  Imports learned patterns from a file.
  """
  @spec import_patterns(String.t()) :: :ok | {:error, String.t()}
  def import_patterns(file_path) do
    GenServer.call(__MODULE__, {:import_patterns, file_path})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      resolution_history: [],
      preference_model: build_empty_model(),
      pattern_cache: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:record_resolution, conflict, chosen_resolution, opts}, state) do
    record = build_resolution_record(conflict, chosen_resolution, opts)

    new_history = [record | state.resolution_history] |> Enum.take(1000)
    new_model = update_preference_model(state.preference_model, record)

    new_state = %{
      state
      | resolution_history: new_history,
        preference_model: new_model,
        pattern_cache: %{}
    }

    Logger.debug(
      "Recorded resolution for #{conflict.file}, total history: #{length(new_history)}"
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:predict_resolution, conflict}, _from, state) do
    result = make_prediction(conflict, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_preferences, _from, state) do
    {:reply, state.preference_model, state}
  end

  @impl true
  def handle_call({:get_history, filters}, _from, state) do
    filtered = filter_history(state.resolution_history, filters)
    {:reply, filtered, state}
  end

  @impl true
  def handle_call(:clear_history, _from, state) do
    new_state = %{
      state
      | resolution_history: [],
        preference_model: build_empty_model(),
        pattern_cache: %{}
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:export_patterns, file_path}, _from, state) do
    # Convert tuples to serializable format
    serializable_history =
      state.resolution_history
      |> Enum.map(&make_serializable/1)

    serializable_model = make_model_serializable(state.preference_model)

    export_data = %{
      history: serializable_history,
      model: serializable_model,
      exported_at: DateTime.utc_now()
    }

    result =
      case Jason.encode(export_data, pretty: true) do
        {:ok, json} ->
          File.write(file_path, json)

        error ->
          error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:import_patterns, file_path}, _from, state) do
    result =
      case File.read(file_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, data} ->
              new_state = %{
                state
                | resolution_history: data["history"] || [],
                  preference_model: atomize_keys(data["model"]) || build_empty_model(),
                  pattern_cache: %{}
              }

              {:reply, :ok, new_state}

            error ->
              {:reply, error, state}
          end

        error ->
          {:reply, error, state}
      end

    case result do
      {:reply, :ok, new_state} -> {:reply, :ok, new_state}
      {:reply, error, _} -> {:reply, error, state}
    end
  end

  # Private Functions

  defp build_resolution_record(conflict, chosen_resolution, opts) do
    chosen_provider =
      case chosen_resolution do
        {:accept, provider} -> provider
        _ -> nil
      end

    %{
      conflict_signature: generate_conflict_signature(conflict),
      file_path: conflict.file,
      file_type: Path.extname(conflict.file),
      conflict_type: conflict.type,
      providers: conflict.providers,
      chosen_resolution: chosen_resolution,
      chosen_provider: chosen_provider,
      timestamp: DateTime.utc_now(),
      context: Keyword.get(opts, :context, %{})
    }
  end

  defp generate_conflict_signature(conflict) do
    # Create a signature based on conflict characteristics
    components = [
      conflict.type,
      conflict.file,
      Enum.sort(conflict.providers) |> Enum.join(",")
    ]

    :crypto.hash(:sha256, Enum.join(components, "|"))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp build_empty_model do
    %{
      by_file_type: %{},
      by_provider: %{},
      by_conflict_type: %{},
      overall_accuracy: 0.0,
      total_resolutions: 0
    }
  end

  defp update_preference_model(model, record) do
    %{
      by_file_type: update_file_type_preferences(model.by_file_type, record),
      by_provider: update_provider_preferences(model.by_provider, record),
      by_conflict_type: update_conflict_type_preferences(model.by_conflict_type, record),
      overall_accuracy: model.overall_accuracy,
      total_resolutions: model.total_resolutions + 1
    }
  end

  defp update_file_type_preferences(prefs, record) do
    file_type = record.file_type

    current = Map.get(prefs, file_type, %{count: 0, resolutions: %{}})

    resolution_key = resolution_to_key(record.chosen_resolution)

    updated_resolutions =
      Map.update(current.resolutions, resolution_key, 1, &(&1 + 1))

    Map.put(prefs, file_type, %{
      count: current.count + 1,
      resolutions: updated_resolutions
    })
  end

  defp update_provider_preferences(prefs, record) do
    if record.chosen_provider do
      provider = record.chosen_provider

      current = Map.get(prefs, provider, %{chosen_count: 0, total_conflicts: 0})

      Map.put(prefs, provider, %{
        chosen_count: current.chosen_count + 1,
        total_conflicts: current.total_conflicts + 1
      })
    else
      prefs
    end
  end

  defp update_conflict_type_preferences(prefs, record) do
    conflict_type = record.conflict_type

    current = Map.get(prefs, conflict_type, %{count: 0, resolutions: %{}})

    resolution_key = resolution_to_key(record.chosen_resolution)

    updated_resolutions =
      Map.update(current.resolutions, resolution_key, 1, &(&1 + 1))

    Map.put(prefs, conflict_type, %{
      count: current.count + 1,
      resolutions: updated_resolutions
    })
  end

  defp resolution_to_key({:accept, provider}), do: {:accept, provider}
  defp resolution_to_key({:merge, strategy}), do: {:merge, strategy}
  defp resolution_to_key({:custom, _}), do: :custom
  defp resolution_to_key(other), do: other

  defp make_prediction(conflict, state) do
    if state.preference_model.total_resolutions < 5 do
      {:error, :insufficient_data}
    else
      # Try different prediction methods and combine their scores
      predictions = [
        predict_by_file_type(conflict, state.preference_model),
        predict_by_conflict_type(conflict, state.preference_model),
        predict_by_provider_history(conflict, state.preference_model),
        predict_by_similar_conflicts(conflict, state.resolution_history)
      ]

      # Combine predictions with weighted average
      combined = combine_predictions(predictions)

      case combined do
        {resolution, confidence} when confidence > 0.3 ->
          {:ok, resolution, confidence}

        _ ->
          {:error, :insufficient_data}
      end
    end
  end

  defp predict_by_file_type(conflict, model) do
    file_type = Path.extname(conflict.file)

    case Map.get(model.by_file_type, file_type) do
      nil ->
        nil

      data ->
        # Find most common resolution for this file type
        most_common =
          data.resolutions
          |> Enum.max_by(fn {_res, count} -> count end, fn -> nil end)

        if most_common do
          {resolution, count} = most_common
          confidence = count / data.count
          {resolution, confidence, 0.3}
        else
          nil
        end
    end
  end

  defp predict_by_conflict_type(conflict, model) do
    case Map.get(model.by_conflict_type, conflict.type) do
      nil ->
        nil

      data ->
        most_common =
          data.resolutions
          |> Enum.max_by(fn {_res, count} -> count end, fn -> nil end)

        if most_common do
          {resolution, count} = most_common
          confidence = count / data.count
          {resolution, confidence, 0.25}
        else
          nil
        end
    end
  end

  defp predict_by_provider_history(conflict, model) do
    # Find which provider is most often chosen
    provider_scores =
      conflict.providers
      |> Enum.map(fn provider ->
        case Map.get(model.by_provider, provider) do
          nil -> {provider, 0.0}
          data -> {provider, data.chosen_count / max(data.total_conflicts, 1)}
        end
      end)
      |> Enum.max_by(fn {_p, score} -> score end, fn -> nil end)

    if provider_scores do
      {provider, score} = provider_scores

      if score > 0.3 do
        {{:accept, provider}, score, 0.25}
      else
        nil
      end
    else
      nil
    end
  end

  defp predict_by_similar_conflicts(conflict, history) do
    # Find similar past conflicts
    similar =
      history
      |> Enum.filter(fn record ->
        record.file_type == Path.extname(conflict.file) and
          record.conflict_type == conflict.type
      end)
      |> Enum.take(20)

    if length(similar) >= 3 do
      # Find most common resolution among similar conflicts
      resolution_counts =
        similar
        |> Enum.group_by(& &1.chosen_resolution)
        |> Enum.map(fn {res, records} -> {res, length(records)} end)
        |> Enum.max_by(fn {_res, count} -> count end, fn -> nil end)

      if resolution_counts do
        {resolution, count} = resolution_counts
        confidence = count / length(similar)
        {resolution, confidence, 0.2}
      else
        nil
      end
    else
      nil
    end
  end

  defp combine_predictions(predictions) do
    valid_predictions = Enum.reject(predictions, &is_nil/1)

    if Enum.empty?(valid_predictions) do
      {nil, 0.0}
    else
      # Group by resolution and calculate weighted confidence
      predictions_by_resolution =
        valid_predictions
        |> Enum.group_by(fn {res, _conf, _weight} -> res end)

      # Find resolution with highest combined weighted confidence
      predictions_by_resolution
      |> Enum.map(fn {resolution, preds} ->
        combined_confidence =
          preds
          |> Enum.map(fn {_res, conf, weight} -> conf * weight end)
          |> Enum.sum()

        {resolution, combined_confidence}
      end)
      |> Enum.max_by(fn {_res, conf} -> conf end, fn -> {nil, 0.0} end)
    end
  end

  defp filter_history(history, filters) do
    history
    |> Enum.filter(fn record ->
      Enum.all?(filters, fn {key, value} ->
        case key do
          :file_type -> record.file_type == value
          :conflict_type -> record.conflict_type == value
          :provider -> value in record.providers
          :since -> DateTime.compare(record.timestamp, value) != :lt
          _ -> true
        end
      end)
    end)
  end

  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      {key, atomize_keys(v)}
    end)
    |> Map.new()
  rescue
    ArgumentError -> map
  end

  defp atomize_keys(value), do: value

  defp make_serializable(record) when is_map(record) do
    record
    |> Map.update(:chosen_resolution, nil, &resolution_to_serializable/1)
    |> Map.update(:timestamp, nil, &DateTime.to_iso8601/1)
  end

  defp resolution_to_serializable({:accept, provider}) do
    %{"type" => "accept", "provider" => to_string(provider)}
  end

  defp resolution_to_serializable({:merge, strategy}) when is_atom(strategy) do
    %{"type" => "merge", "strategy" => to_string(strategy)}
  end

  defp resolution_to_serializable({:merge, strategy}) when is_map(strategy) do
    %{"type" => "merge", "strategy" => strategy}
  end

  defp resolution_to_serializable({:custom, content}) do
    %{"type" => "custom", "content" => content}
  end

  defp resolution_to_serializable(other), do: to_string(other)

  defp make_model_serializable(model) do
    model
    |> Map.update(:by_file_type, %{}, &make_preferences_serializable/1)
    |> Map.update(:by_conflict_type, %{}, &make_preferences_serializable/1)
  end

  defp make_preferences_serializable(prefs) do
    prefs
    |> Enum.map(fn {key, value} ->
      serializable_value =
        case value do
          %{resolutions: resolutions} = v ->
            %{v | resolutions: make_resolutions_serializable(resolutions)}

          v ->
            v
        end

      {to_string(key), serializable_value}
    end)
    |> Map.new()
  end

  defp make_resolutions_serializable(resolutions) do
    resolutions
    |> Enum.map(fn {res_key, count} ->
      {resolution_key_to_string(res_key), count}
    end)
    |> Map.new()
  end

  defp resolution_key_to_string({:accept, provider}), do: "accept_#{provider}"
  defp resolution_key_to_string({:merge, strategy}), do: "merge_#{strategy}"
  defp resolution_key_to_string(:custom), do: "custom"
  defp resolution_key_to_string(other), do: to_string(other)
end
