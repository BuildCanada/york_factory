module PublicApi
  # Relative links that reproduce a response (Links.self, PageLinks): the
  # request's own parameters in the order sent, with `as_of` pinned last.
  module Links
    module_function

    def url(path, params)
      pairs = params.reject { |_, v| v.nil? }
      return path if pairs.empty?

      "#{path}?#{pairs.map { |k, v| "#{escape(k)}=#{escape(v)}" }.join('&')}"
    end

    # Commas separate list values in this API, so they stay readable.
    def escape(value) = URI.encode_www_form_component(value.to_s).gsub("%2C", ",")
  end
end
