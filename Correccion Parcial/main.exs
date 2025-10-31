Code.require_file(Path.join(__DIR__, "pieza.exs"))
Code.require_file(Path.join(__DIR__, "movimiento.exs"))
Code.require_file(Path.join(__DIR__, "inventario_lib.exs"))

defmodule MainCLI do
  def start_interactive() do
    estado = %{piezas: nil, movs: nil}
    loop(estado)
  end

  defp loop(estado) do
    IO.puts("")
    IO.puts("=== Inventario (modo interactivo) ===")
    IO.puts("1) Cargar piezas.csv")
    IO.puts("2) Cargar movimientos.csv")
    IO.puts("3) Aplicar movimientos y guardar inventario_actual.csv")
    IO.puts("4) Contar piezas con stock menor que t")
    IO.puts("5) Sumar unidades movidas en rango [fini, ffin]")
    IO.puts("6) Deduplicar piezas por codigo y guardar piezas_dedup.csv")
    IO.puts("7) Mostrar estado cargado")
    IO.puts("8) Agregar pieza manualmente (no guarda CSV, solo en memoria)")
    IO.puts("9) Salir")
    opcion = read_line("> ")
    case opcion do
      "1" ->
        path = read_line("Ruta de piezas.csv: ")
        case Inventario.leer_piezas(path) do
          {:ok, ps} ->
            IO.puts("OK: " <> Integer.to_string(length(ps)) <> " piezas cargadas")
            loop(%{estado | piezas: ps})
          {:error, e} ->
            IO.puts(":error " <> inspect(e))
            loop(estado)
        end
      "2" ->
        path = read_line("Ruta de movimientos.csv: ")
        case Inventario.leer_movimientos(path) do
          {:ok, ms} ->
            IO.puts("OK: " <> Integer.to_string(length(ms)) <> " movimientos cargados")
            loop(%{estado | movs: ms})
          {:error, e} ->
            IO.puts(":error " <> inspect(e))
            loop(estado)
        end
      "3" ->
        case {estado.piezas, estado.movs} do
          {nil, _} -> IO.puts("Primero cargue piezas (opción 1)"); loop(estado)
          {_, nil} -> IO.puts("Primero cargue movimientos (opción 2)"); loop(estado)
          {ps, ms} ->
            case Inventario.aplicar_movimientos(ps, ms) do
              {:ok, nuevas} ->
                case Inventario.escribir_inventario(Path.join(File.cwd!(), "inventario_actual.csv"), nuevas) do
                  :ok -> IO.puts("inventario_actual.csv generado"); loop(%{estado | piezas: nuevas})
                  {:error, e} -> IO.puts(":error " <> inspect(e)); loop(estado)
                end
              {:error, e} -> IO.puts(":error " <> inspect(e)); loop(estado)
            end
        end
      "4" ->
        case estado.piezas do
          nil -> IO.puts("Primero cargue piezas (opción 1)"); loop(estado)
          ps ->
            t = read_line("Umbral t (entero): ")
            case Integer.parse(t) do
              {n, rest} when rest == "" ->
                case Inventario.contar_stock_menor(ps, n) do
                  {:ok, c} -> IO.puts("Cantidad: " <> Integer.to_string(c)); loop(estado)
                  {:error, e} -> IO.puts(":error " <> inspect(e)); loop(estado)
                end
              _ -> IO.puts("t inválido"); loop(estado)
            end
        end
      "5" ->
        case estado.movs do
          nil -> IO.puts("Primero cargue movimientos (opción 2)"); loop(estado)
          ms ->
            fi = read_line("Fecha inicio (YYYY-MM-DD): ")
            ff = read_line("Fecha fin (YYYY-MM-DD): ")
            case Inventario.total_movido_en_rango(ms, fi, ff) do
              {:ok, total} -> IO.puts("Total movido: " <> Integer.to_string(total)); loop(estado)
              {:error, e} -> IO.puts(":error " <> inspect(e)); loop(estado)
            end
        end
      "6" ->
        case estado.piezas do
          nil -> IO.puts("Primero cargue piezas (opción 1)"); loop(estado)
          ps ->
            case Inventario.dedup_por_codigo(ps) do
              {:ok, lista} ->
                case Inventario.escribir_inventario(Path.join(File.cwd!(), "piezas_dedup.csv"), lista) do
                  :ok -> IO.puts("piezas_dedup.csv generado"); loop(%{estado | piezas: lista})
                  {:error, e} -> IO.puts(":error " <> inspect(e)); loop(estado)
                end
              {:error, e} -> IO.puts(":error " <> inspect(e)); loop(estado)
            end
        end
      "7" ->
        IO.puts("Piezas cargadas: " <> count_opt(estado.piezas))
        IO.puts("Movimientos cargados: " <> count_opt(estado.movs))
        loop(estado)
      "8" ->
        codigo = read_line("codigo: ")
        nombre = read_line("nombre: ")
        valor = read_line("valor (entero): ")
        unidad = read_line("unidad: ")
        stock = read_line("stock (entero): ")
        case Inventario.crear_pieza(codigo, nombre, valor, unidad, stock) do
          {:ok, p} ->
            case Inventario.agregar_pieza(estado.piezas, p) do
              {:ok, lista} -> IO.puts("Pieza agregada"); loop(%{estado | piezas: lista})
              {:error, e} -> IO.puts(":error " <> inspect(e)); loop(estado)
            end
          {:error, e} -> IO.puts(":error " <> inspect(e)); loop(estado)
        end
      "9" -> :ok
      _ -> IO.puts("Opción inválida"); loop(estado)
    end
  end

  defp count_opt(nil), do: "0"
  defp count_opt(list), do: Integer.to_string(length(list))

  defp read_line(prompt) do
    IO.write(prompt)
    case IO.gets("") do
      :eof -> ""
      nil -> ""
      s -> String.trim(s)
    end
  end
end

case System.argv() do
  [] ->
    MainCLI.start_interactive()
  [piezas_path] ->
    case Inventario.leer_piezas(piezas_path) do
      {:ok, piezas} -> IO.puts(length(piezas))
      {:error, e} -> IO.puts(":error " <> inspect(e))
    end
  [piezas_path, movimientos_path] ->
    with {:ok, piezas} <- Inventario.leer_piezas(piezas_path),
         {:ok, movs} <- Inventario.leer_movimientos(movimientos_path),
         {:ok, nuevas} <- Inventario.aplicar_movimientos(piezas, movs),
         :ok <- Inventario.escribir_inventario(Path.join(__DIR__, "inventario_actual.csv"), nuevas) do
      IO.puts("ok")
    else
      {:error, e} -> IO.puts(":error " <> inspect(e))
      e -> IO.puts(":error " <> inspect(e))
    end
  [piezas_path, "menor", t] ->
    with {:ok, piezas} <- Inventario.leer_piezas(piezas_path),
         {:ok, ti} <- (case Integer.parse(t) do {n, rest} when rest == "" -> {:ok, n}; _ -> {:error, :umbral} end),
         {:ok, c} <- Inventario.contar_stock_menor(piezas, ti) do
      IO.puts(Integer.to_string(c))
    else
      {:error, e} -> IO.puts(":error " <> inspect(e))
    end
  [movs_path, "rango", fini, ffin] ->
    with {:ok, movs} <- Inventario.leer_movimientos(movs_path),
         {:ok, total} <- Inventario.total_movido_en_rango(movs, fini, ffin) do
      IO.puts(Integer.to_string(total))
    else
      {:error, e} -> IO.puts(":error " <> inspect(e))
    end
  [piezas_path, "dedup"] ->
    case Inventario.leer_piezas(piezas_path) do
      {:ok, piezas} ->
        {:ok, lista} = Inventario.dedup_por_codigo(piezas)
        :ok = Inventario.escribir_inventario(Path.join(__DIR__, "piezas_dedup.csv"), lista)
        IO.puts("ok")
      {:error, e} -> IO.puts(":error " <> inspect(e))
    end
  _ ->
    IO.puts("uso: elixir main.exs <piezas.csv> [movimientos.csv]\n" <>
            "     elixir main.exs <piezas.csv> menor <t>\n" <>
            "     elixir main.exs <movimientos.csv> rango <YYYY-MM-DD> <YYYY-MM-DD>\n" <>
            "     elixir main.exs <piezas.csv> dedup")
end

