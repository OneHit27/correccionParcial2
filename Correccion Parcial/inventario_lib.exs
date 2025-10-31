defmodule Inventario do

  defp parse_int(cadena) when is_binary(cadena) do
    texto = String.trim(cadena)
    case Integer.parse(texto) do
      {num, ""} -> {:ok, num}
      _ -> {:error, :entero_invalido}
    end
  end

  defp tipo_valido?("ENTRADA"), do: true
  defp tipo_valido?("SALIDA"), do: true
  defp tipo_valido?(_), do: false

  defp parse_fecha(fecha_str) when is_binary(fecha_str) do
    partes = String.split(String.trim(fecha_str), "-")
    case partes do
      [yy, mm, dd] ->
        with {:ok, y} <- parse_int(yy),
             {:ok, m} <- parse_int(mm),
             {:ok, d} <- parse_int(dd),
             true <- y > 0 and m in 1..12 and d in 1..31 do
          {:ok, {y, m, d}}
        else
          false -> {:error, :fecha_fuera_de_rango}
          {:error, _} -> {:error, :fecha_invalida}
        end
      _ -> {:error, :formato_fecha}
    end
  end

  defp fecha_key({a, m, d}), do: a * 10_000 + m * 100 + d

  # Lector de piezas.csv
  def leer_piezas(path) do
    case File.read(path) do
      {:ok, contenido} ->
        lineas = String.split(contenido, "\n")
        procesar_piezas(lineas, [])
      {:error, motivo} ->
        {:error, {:file_error, motivo}}
    end
  end

  defp procesar_piezas([], acc), do: {:ok, invertir_lista(acc, [])}
  defp procesar_piezas([linea | tail], acc) do
    texto = String.trim(linea)
    case texto do
      "" -> procesar_piezas(tail, acc)
      _ ->
        case parsear_pieza_linea(texto) do
          {:ok, pieza} -> procesar_piezas(tail, [pieza | acc])
          {:error, e} -> {:error, {:linea_invalida, e, texto}}
        end
    end
  end

  defp parsear_pieza_linea(linea) do
    campos = String.split(linea, ",")
    case campos do
      [codigo, nombre, valor, unidad, stock] ->
        with {:ok, v} <- parse_int(valor),
             {:ok, s} <- parse_int(stock) do
          {:ok, %Pieza{
            codigo: String.trim(codigo),
            nombre: String.trim(nombre),
            valor: v,
            unidad: String.trim(unidad),
            stock: s
          }}
        else
          {:error, e} -> {:error, e}
        end
      _ -> {:error, :campos_pieza}
    end
  end

  # Contar piezas con stock menor a umbral

  def contar_stock_menor(_, t) when not is_integer(t),
    do: {:error, :umbral_invalido}

  def contar_stock_menor(piezas, t),
    do: {:ok, contar_rec(piezas, t, 0)}

  defp contar_rec([], _t, acc), do: acc
  defp contar_rec([%Pieza{stock: s} | tail], t, acc) do
    nuevo = if s < t, do: acc + 1, else: acc
    contar_rec(tail, t, nuevo)
  end

  # Lector de movimientos.csv

  def leer_movimientos(path) do
    case File.read(path) do
      {:ok, datos} ->
        filas = String.split(datos, "\n")
        procesar_movs(filas, [])
      {:error, razon} ->
        {:error, {:file_error, razon}}
    end
  end

  defp procesar_movs([], acc), do: {:ok, invertir_lista(acc, [])}
  defp procesar_movs([linea | tail], acc) do
    texto = String.trim(linea)
    case texto do
      "" -> procesar_movs(tail, acc)
      _ ->
        case parsear_mov_linea(texto) do
          {:ok, mov} -> procesar_movs(tail, [mov | acc])
          {:error, e} -> {:error, {:linea_invalida, e, texto}}
        end
    end
  end

  defp parsear_mov_linea(linea) do
    partes = String.split(linea, ",")
    case partes do
      [codigo, tipo, cantidad, fecha] ->
        tipo = String.trim(tipo)
        with true <- tipo_valido?(tipo) or {:error, :tipo_invalido},
             {:ok, cant} <- parse_int(cantidad),
             true <- cant > 0 or {:error, :cantidad_no_positiva},
             {:ok, _} <- parse_fecha(fecha) do
          {:ok, %Movimiento{codigo: String.trim(codigo), tipo: tipo, cantidad: cant, fecha: String.trim(fecha)}}
        else
          {:error, e} -> {:error, e}
          false -> {:error, :tipo_invalido}
        end
      _ -> {:error, :campos_mov}
    end
  end

  # Aplicar movimientos a piezas

  def aplicar_movimientos(piezas, movimientos),
    do: aplicar_recursivo(piezas, movimientos)

  defp aplicar_recursivo(piezas, []), do: {:ok, piezas}
  defp aplicar_recursivo(piezas, [%Movimiento{} = m | tail]) do
    delta = if m.tipo == "ENTRADA", do: m.cantidad, else: -m.cantidad
    case actualizar_stock(piezas, m.codigo, delta, []) do
      {:ok, nuevas} -> aplicar_recursivo(nuevas, tail)
      {:error, e} -> {:error, e}
    end
  end

  defp actualizar_stock([], codigo, _delta, _acc),
    do: {:error, {:pieza_no_encontrada, codigo}}

  defp actualizar_stock([%Pieza{codigo: c} = p | tail], codigo, delta, acc) do
    if c == codigo do
      nueva = %Pieza{p | stock: p.stock + delta}
      {:ok, invertir_lista(acc, [nueva | tail])}
    else
      actualizar_stock(tail, codigo, delta, [p | acc])
    end
  end

  # Escribir inventario en CSV

  def escribir_inventario(path, piezas) do
    texto = piezas_a_csv(piezas, [])
    File.write(path, texto)
  end

  defp piezas_a_csv([], acc), do: to_string(invertir_texto(acc, []))
  defp piezas_a_csv([%Pieza{} = p | tail], acc) do
    fila =
      "#{p.codigo},#{p.nombre},#{Integer.to_string(p.valor)},#{p.unidad},#{Integer.to_string(p.stock)}\n"

    piezas_a_csv(tail, [fila | acc])
  end

  # Total movido en rango

  def total_movido_en_rango(movs, fini, ffin) do
    with {:ok, fi} <- parse_fecha(fini),
         {:ok, ff} <- parse_fecha(ffin) do
      clave_i = fecha_key(fi)
      clave_f = fecha_key(ff)
      {:ok, sumar_rango(movs, clave_i, clave_f, 0)}
    else
      {:error, e} -> {:error, e}
    end
  end

  defp sumar_rango([], _fi, _ff, acc), do: acc
  defp sumar_rango([%Movimiento{fecha: f, cantidad: c} | tail], fi, ff, acc) do
    case parse_fecha(f) do
      {:ok, fecha_tuple} ->
        fk = fecha_key(fecha_tuple)
        nuevo_acc = if fk in fi..ff, do: acc + c, else: acc
        sumar_rango(tail, fi, ff, nuevo_acc)
      _ -> sumar_rango(tail, fi, ff, acc)
    end
  end

  # Eliminar duplicados

  def dedup_por_codigo(piezas),
    do: {:ok, invertir_lista(eliminar_duplicados(piezas, [], []), [])}

  defp eliminar_duplicados([], _vistos, acc), do: acc
  defp eliminar_duplicados([%Pieza{codigo: c} = p | tail], vistos, acc) do
    if contiene?(vistos, c) do
      eliminar_duplicados(tail, vistos, acc)
    else
      eliminar_duplicados(tail, [c | vistos], [p | acc])
    end
  end

  defp contiene?([], _), do: false
  defp contiene?([x | xs], y), do: if x == y, do: true, else: contiene?(xs, y)

  # Utilidades recursivas

  defp invertir_lista([], acc), do: acc
  defp invertir_lista([h | t], acc), do: invertir_lista(t, [h | acc])

  defp invertir_texto([], acc), do: acc
  defp invertir_texto([h | t], acc), do: invertir_texto(t, [h | acc])

  # Crear y agregar piezas

  def crear_pieza(codigo, nombre, valor_str, unidad, stock_str) do
    codigo = String.trim(codigo || "")
    nombre = String.trim(nombre || "")
    unidad = String.trim(unidad || "")

    with true <- codigo != "" or {:error, :codigo_vacio},
         true <- nombre != "" or {:error, :nombre_vacio},
         true <- unidad != "" or {:error, :unidad_vacia},
         {:ok, valor} <- parse_int(to_string(valor_str || "")),
         {:ok, stock} <- parse_int(to_string(stock_str || "")) do
      {:ok, %Pieza{codigo: codigo, nombre: nombre, valor: valor, unidad: unidad, stock: stock}}
    else
      {:error, e} -> {:error, e}
      false -> {:error, :datos_invalidos}
    end
  end

  def agregar_pieza(nil, %Pieza{} = p), do: {:ok, [p]}
  def agregar_pieza(lista, %Pieza{} = p) do
    if existe_codigo?(lista, p.codigo) do
      {:error, {:codigo_duplicado, p.codigo}}
    else
      {:ok, [p | lista]}
    end
  end

  defp existe_codigo?([], _), do: false
  defp existe_codigo?([%Pieza{codigo: c} | tail], codigo),
    do: if c == codigo, do: true, else: existe_codigo?(tail, codigo)
end
